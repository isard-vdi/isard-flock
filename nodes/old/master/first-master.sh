#!/bin/bash

## yum install -y git && git clone https://github.com/isard-vdi/isard-flock && cd isard-flock/nodes/master/ && bash first-master.sh

host=1
# viewers internet drbd nas
interfaces=(eth0 - eth2 eth1)

raid_level=1
raid_devs=(/dev/vdb /dev/vdc)

# Remove al connections
remove_all_if(){
	nmcli --fields UUID,TIMESTAMP-REAL con show |  awk '{print $1}' | while read line; do nmcli con delete uuid  $line;    done
	rm -rf /etc/sysconfig/network-scripts/ifcfg-{nas,drbd,viewers,internet}
}

# Set nas & drbd connections
set_if(){
	# original final
	if [[ $2 == "nas" ]] || [[ $2 == "drbd" ]]; then
		net=0
		if [[ $2 == "drbd" ]]; then net=1; fi
		nmcli con add con-name "$2" ifname $1 type ethernet ip4 172.31.$net.1$host/24
	else
		nmcli con add con-name "$2" ifname $1 type ethernet ipv4.method auto
	fi
	nmcli con mod "$2" connection.interface-name "$2"
	nmcli con mod "$2" ipv6.method ignore
	if [[ $2 == "nas" ]] || [[ $2 == "drbd" ]]; then
		nmcli con mod "$2" 802-3-ethernet.mtu 9000
	fi
	MAC=$(cat /sys/class/net/$1/address)
	echo -n 'HWADDR="'$MAC\" >> /etc/sysconfig/network-scripts/ifcfg-$2
	ip link set $1 down
	ip link set $1 name $2
	if [[ $2 == "nas" ]] || [[ $2 == "drbd" ]]; then
		ip link set $2 mtu 9000
	fi
	ip link set $2 up
}

systemctl disable --now firewalld
sed -i s/^SELINUX=.*$/SELINUX=disabled/ /etc/selinux/config && setenforce 0
setenforce 0

# raid
set_raid(){
	yum install -y mdadm lvm2
	for d in "${raid_devs[@]}" 
	do
		dd if=/dev/zero of=$d bs=2048 count=4096
	done
	yes | mdadm --create --verbose /dev/md0 --level=$raid_level --raid-devices=${#raid_devs[@]} ${raid_devs[@]}
	sudo mdadm --detail --scan > /etc/mdadm.conf
	pvcreate /dev/md0
	vgcreate drbdpool /dev/md0
}


# Hostname
echo "if$host" > /etc/hostname
sysctl -w kernel.hostname=if$host
cp ../hosts /etc/hosts

ssh-keygen -t dsa -f ~/.ssh/id_dsa -N ""
cp ~/.ssh/id_dsa.pub ~/.ssh/authorized_keys
yum install -y sshpass rsync nc

# Interface set
ifnames=(viewers internet drbd nas)
iifnames=0
remove_all_if
for i in "${interfaces[@]}"
do
	if [[ $i != "-" ]]; then
		set_if $i ${ifnames[$iifnames]}
	fi
	iifnames=$((iifnames+1))
done

systemctl enable --now chronyd
# Raid
set_raid

# DRBD
rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
yum install -y https://www.elrepo.org/elrepo-release-7.0-3.el7.elrepo.noarch.rpm
yum install -y kmod-drbd90 drbd90-utils

yum install -y git java-1.8.0-openjdk
cd ../../linstor
rpm -ivh linstor-common-0.9.12-1.el7.noarch.rpm  linstor-controller-0.9.12-1.el7.noarch.rpm  linstor-satellite-0.9.12-1.el7.noarch.rpm python-linstor-0.9.8-1.noarch.rpm
rpm -ivh linstor-client-0.9.8-1.noarch.rpm
cd ../nodes/master
systemctl enable --now linstor-controller
sleep 5
echo "[global]" > /etc/linstor/linstor-client.conf
echo "controllers=if1,if2,if3,if4,if5,if6,if7,if8" >> /etc/linstor/linstor-client.conf
systemctl enable --now linstor-satellite
sleep 5
linstor node create if$host 172.31.1.1$host

linstor storage-pool create lvm if$host data drbdpool
linstor resource-definition create isard
linstor volume-definition create isard 470M
linstor resource create isard --auto-place 1 --storage-pool data
sleep 5
mkfs.ext4 /dev/drbd/by-res/isard/0

# PCS
# PACEMAKER
yum install -y corosync pacemaker pcs python-pycurl fence-agents-apc fence-agents-apc-snmp
systemctl enable pcsd
systemctl enable corosync
systemctl enable pacemaker
systemctl start pcsd
usermod --password $(echo isard-flock | openssl passwd -1 -stdin) hacluster
pcs cluster auth if$host <<EOF
hacluster
isard-flock
EOF


pcs cluster setup --name isard if$host
pcs cluster enable
pcs cluster start if$host

## LINSTORDB STORAGE
linstor resource-definition create linstordb
linstor volume-definition create linstordb 250M
linstor resource create linstordb --auto-place 1 --storage-pool data

systemctl disable --now linstor-controller
rsync -avp /var/lib/linstor /tmp/
mkfs.ext4 /dev/drbd/by-res/linstordb/0
rm -rf /var/lib/linstor/*
mount /dev/drbd/by-res/linstordb/0 /var/lib/linstor
rsync -avp /tmp/linstor/ /var/lib/linstor/

#pcs stonith create stonith-rsa-if1 fence_rsa action=off ipaddr="if1" login=root pcmk_host_list=if1 secure=true
pcs resource create linstordb-drbd ocf:linbit:drbd drbd_resource=linstordb op monitor interval=15s role=Master op monitor interval=30s role=Slave
pcs resource master linstordb-drbd-clone linstordb-drbd master-max=1 master-node-max=1 clone-max=8 clone-node-max=1 notify=true
pcs resource create linstordb-fs Filesystem \
        device="/dev/drbd/by-res/linstordb/0" directory="/var/lib/linstor" \
        fstype="ext4" "options=defaults,noatime,nodiratime,noquota" op monitor interval=10s
pcs resource create linstor-controller systemd:linstor-controller

pcs resource group add linstor linstordb-fs linstor-controller
pcs constraint order promote linstordb-drbd-clone then linstor INFINITY \
	require-all=true symmetrical=true \
	setoptions kind=Mandatory
pcs constraint colocation add \
	linstor with master linstordb-drbd-clone INFINITY 

pcs property set no-quorum-policy=ignore

#~ pcs resource create linstordb-fs Filesystem \
        #~ device="/dev/drbdpool/linstordb_00000" directory="/var/lib/linstor" \
        #~ fstype="ext4" "options=defaults,noatime,nodiratime,noquota" op monitor interval=10s


## ISARD STORAGE
mkdir /opt/isard
pcs resource create isard_fs Filesystem device="/dev/drbd/by-res/isard/0" directory="/opt/isard" fstype="ext4" "options=defaults,noatime,nodiratime,noquota" op monitor interval=10s

yum install nfs-utils -y
pcs resource create nfs-daemon systemd:nfs-server 
pcs resource create nfs-root exportfs \
clientspec=172.31.0.0/255.255.255.0 \
options=rw,crossmnt,async,wdelay,no_root_squash,no_subtree_check,sec=sys,rw,secure,no_root_squash,no_all_squash \
directory=/opt/ \
fsid=0

pcs resource create isard_data exportfs \
clientspec=172.31.0.0/255.255.255.0 \
wait_for_leasetime_on_stop=true \
options=rw,mountpoint,async,wdelay,no_root_squash,no_subtree_check,sec=sys,rw,secure,no_root_squash,no_all_squash directory=/opt/isard \
fsid=11 \
op monitor interval=30s


pcs resource create isard-ip ocf:heartbeat:IPaddr2 ip=172.31.0.1 cidr_netmask=32 nic=nas:0  op monitor interval=30 


pcs resource group add server linstordb-fs linstor-controller isard_fs nfs-daemon nfs-root isard_data isard-ip
pcs constraint order set linstordb-fs linstor-controller isard_fs nfs-daemon nfs-root isard_data isard-ip

pcs property set stonith-enabled=false

## nfs mounts
pcs resource create nfs-client Filesystem \
        device=isard-nas:/isard directory="/opt/isard" \
        fstype="nfs" "options=defaults,noatime" op monitor interval=10s
pcs resource clone nfs-client clone-max=8 clone-node-max=8 notify=true
pcs constraint colocation add nfs-client-clone with isard-ip -INFINITY

# DOCKER
#~ sudo yum remove docker \
                  #~ docker-client \
                  #~ docker-client-latest \
                  #~ docker-common \
                  #~ docker-latest \
                  #~ docker-latest-logrotate \
                  #~ docker-logrotate \
                  #~ docker-engine
#~ sudo yum install -y yum-utils \
  #~ device-mapper-persistent-data \
  #~ lvm2
#~ sudo yum-config-manager \
    #~ --add-repo \
    #~ https://download.docker.com/linux/centos/docker-ce.repo
#~ sudo yum install -y docker-ce docker-ce-cli containerd.io

#~ sudo curl -L "https://github.com/docker/compose/releases/download/1.24.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
#~ chmod +x /usr/local/bin/docker-compose

#~ rpm -ivh linstor/linstor-docker-volume-0.2.0-1.noarch.rpm
#~ systemctl enable --now linstor-docker-volume.socket
#~ systemctl enable --now linstor-docker-volume.service

#~ cp docker/docker-compose.yml /opt/isard
#~ cd /opt/isard
#~ docker-compose up -d

















