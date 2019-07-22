#!/bin/bash

## yum install -y git && git clone https://github.com/isard-vdi/isard-flock && cd isard-flock/nodes/master/ && bash first-master.sh

host=2
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
echo "[global]" > /etc/linstor/linstor-client.conf
echo "controllers=if1,if2,if3,if4,if5,if6,if7,if8" >> /etc/linstor/linstor-client.conf
systemctl enable --now linstor-satellite
sleep 5
linstor node create if$host 172.31.1.1$host
sleep 5
linstor storage-pool create lvm if$host data drbdpool
linstor resource create isard --auto-place 2 --storage-pool data
sleep 5

# PCS
# PACEMAKER
yum install -y corosync pacemaker pcs python-pycurl fence-agents-apc fence-agents-apc-snmp
systemctl enable pcsd
systemctl enable corosync
systemctl enable pacemaker
systemctl start pcsd
usermod --password $(echo isard-flock | openssl passwd -1 -stdin) hacluster
#~ pcs cluster auth if$host <<EOF
#~ hacluster
#~ isard-flock
#~ EOF


#~ pcs cluster setup --name isard if$host
#~ pcs cluster enable
#~ pcs cluster start if$host

## LINSTORDB STORAGE
#linstor resource create linstordb --auto-place 2 --storage-pool data


## ISARD STORAGE
mkdir /opt/isard

yum install nfs-utils -y



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

















