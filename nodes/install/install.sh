#!/bin/bash

# Install on CentOS minimal server

#~ 1. MASTER (RAID+DRBD+PACEMAKER+NAS+DOCKER)
#~ 2. REPLICA (DRBD+PACEMAKER+NAS+DOCKER)
#~ 3. DISKLESS (PACEMAKER+NFS)

# Defaults (If set will bypass tui selection menu)
if_viewers='' 	#'eth0'
if_internet='' 	#'eth1'
if_drbd='' 		#'eth2'
if_nas='' 		#'eth3'

raid_level=-1 	#1
raid_devices=() #(/dev/vdb /dev/vdc)
pv_device='' 	#"/dev/md0"

master_node=-1  # 1 yes, 0 no

## FUNCTIONS
install_base_pkg(){
	systemctl disable --now firewalld
	sed -i s/^SELINUX=.*$/SELINUX=disabled/ /etc/selinux/config && setenforce 0
	setenforce 0
	rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
	yum install -y https://www.elrepo.org/elrepo-release-7.0-3.el7.elrepo.noarch.rpm
	yum install -y nano git sshpass rsync nc dialog
	systemctl enable --now chronyd
}

remove_all_if(){
	nmcli --fields UUID,TIMESTAMP-REAL con show |  awk '{print $1}' | while read line; do nmcli con delete uuid  $line;    done
	rm -rf /etc/sysconfig/network-scripts/ifcfg-{nas,drbd,viewers,internet}
}

get_ifs(){
	i=1
	unset var
	unset interfaces
	system_ifs=(lo viewers internet nas drbd)
	for iface in $(ifconfig | cut -d ' ' -f1| tr ':' '\n' | awk NF)
	do
		if [[ $iface == "" ]] || [[ ${system_ifs[*]} =~ "$iface" ]] ; then continue; fi
		interfaces+=("$iface")
		var="$var $i $iface "
		i=$((i+1))
	done
	var="$var $((${#interfaces[@]}+1)) skip"
}

set_if(){
	# original final
	if [[ $new_if == "nas" ]] || [[ $new_if == "drbd" ]]; then
		net=0
		if [[ $new_if == "drbd" ]]; then net=1; fi
		if [[ $host == 1 ]]; then
			fhost=11
		else
			fhost=254
		fi
		nmcli con add con-name "$new_if" ifname $old_if type ethernet ip4 172.31.$net.$fhost/24
	else
		nmcli con add con-name "$new_if" ifname $old_if type ethernet ipv4.method auto
	fi
	nmcli con mod "$new_if" connection.interface-name "$new_if"
	nmcli con mod "$new_if" ipv6.method ignore
	if [[ $new_if == "nas" ]] || [[ $new_if == "drbd" ]]; then
		nmcli con mod "$new_if" 802-3-ethernet.mtu 9000
	fi
	MAC=$(cat /sys/class/net/$old_if/address)
	echo -n 'HWADDR="'$MAC\" >> /etc/sysconfig/network-scripts/ifcfg-$new_if
	ip link set $old_if down
	ip link set $old_if name $new_if
	if [[ $new_if == "nas" ]] || [[ $new_if == "drbd" ]]; then
		ip link set $new_if mtu 9000
	fi
	ip link set $new_if up
    nmcli con up "$new_if"
	get_ifs
}

set_viewers_if(){
	if [[ $if_viewers == '' ]] ; then
		opt=$(dialog --menu --stdout "Select interface for guests VIEWERS:" 0 0 0 $var )
		if ! [[ $opt -gt ${#interfaces[@]} ]]; then
			old_if=${interfaces[$(($opt-1))]}
			new_if="viewers"
			set_if
		fi
	else
		old_if=$if_viewers
		new_if="viewers"
	fi
}

set_nas_if(){
	if [[ $if_nas == '' ]] ; then
	opt=$(dialog --menu --stdout "Select interface for NAS:" 0 0 0 $var )
		if ! [[ $opt -gt ${#interfaces[@]} ]]; then
			old_if=${interfaces[$(($opt-1))]}
			new_if="nas"
			set_if
		fi
	else
		old_if=$if_nas
		new_if="nas"
	fi		
}

set_drbd_if(){
	if [[ $if_drbd == '' ]] ; then
		opt=$(dialog --menu --stdout "Select interface for DRBD:" 0 0 0 $var )
		if ! [[ $opt -gt ${#interfaces[@]} ]]; then
			old_if=${interfaces[$(($opt-1))]}
			new_if="drbd"
			set_if
		fi
	else
		old_if=$if_drbd
		new_if="drbd"
	fi
}

set_internet_if(){
	if [[ $if_internet == '' ]] ; then
		opt=$(dialog --menu --stdout "Select interface for guests INTERNET:" 0 0 0 $var )
		if ! [[ $opt -gt ${#interfaces[@]} ]]; then
			old_if=${interfaces[$(($opt-1))]}
			new_if="internet"
			set_if
		fi
	else
		old_if=$if_internet
		new_if="internet"
	fi
}

create_raid(){
	yum install -y mdadm
	for d in "${raid_devices[@]}" 
	do
		dd if=/dev/zero of=$d bs=2048 count=4096
	done
	yes | mdadm --create --verbose /dev/md0 --level=$raid_level --raid-devices=${#raid_devices[@]} ${raid_devices[@]}
	sudo mdadm --detail --scan > /etc/mdadm.conf
}

create_drbdpool(){
	yum install -y lvm2
	yum install -y kmod-drbd90 drbd90-utils java-1.8.0-openjdk
	pvcreate $pv_device
	vgcreate drbdpool $pv_device
	rpm -ivh ./resources/python-linstor-0.9.8-1.noarch.rpm \
		./resources/linstor-common-0.9.12-1.el7.noarch.rpm  \
		./resources/linstor-controller-0.9.12-1.el7.noarch.rpm  \
		./resources/linstor-satellite-0.9.12-1.el7.noarch.rpm \
		./resources/linstor-client-0.9.8-1.noarch.rpm
	cp ./resources/linstor-satellite.service /usr/lib/systemd/system
	cp ./resources/linstor-controller.service /usr/lib/systemd/system
	cp ./resources/linstor-client.conf /etc/linstor/
	#~ systemctl enable --now linstor-satellite (it is done when setting it up)
}

set_storage_dialog(){
	var=""
	i=1
	for dev in ${devs[@]}
	do
		if [[ $var == "" ]]; then
			var="$var $i $dev off "
		else
			var="$var $i $dev on "
		fi
		i=$((i+1))
	done

	if [[ ${#devs[@]} -eq 2 ]]; then
		# NO RAID
		cmd=(dialog --menu --stdout "Select storage device:" 0 0 0 )
		options=($var)
		choices=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
		pv_device="dev/${devs[0]}"
		create_drbdpool
	fi
	if [[ ${#devs[@]} -eq 3 ]]; then
		# RAID 1 - 2 DISKS
		cmd=(dialog --separate-output --checklist "Select 2 devices for RAID 1:" 22 76 16)
		options=($var)
		choices=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)		
		for c in $choices
		do
			raid_sdevs="$raid_sdevs /dev/${devs[$(($c-1))]}"
		done
		raid_devices=(${raid_sdevs[@]})
		raid_level=1
		create_raid
		pv_device="/dev/md0"
		create_drbdpool
	fi
	if [[ ${#devs[@]} -eq 4 ]]; then
		# RAID 1 - 2 DISKS + SPARE
		# RAID 5 - 3 DISKS
		echo "Not implemented"
	fi
	if [[ ${#devs[@]} -gt 4 ]]; then
		# RAID 5 - 3 DISKS + SPARE
		# RAID 10 - 4 DISKS
		echo "Not implemented"
	fi

}

set_storage(){
	if [[ $raid_level == -1 ]] ; then
		set_storage_dialog	
	else
		create_raid
	fi	
}

set_pacemaker(){
	yum install -y corosync pacemaker pcs python-pycurl fence-agents-apc fence-agents-apc-snmp
	systemctl enable pcsd
	systemctl enable corosync
	systemctl enable pacemaker
	systemctl start pcsd
}

set_docker(){
	sudo yum remove docker \
					  docker-client \
					  docker-client-latest \
					  docker-common \
					  docker-latest \
					  docker-latest-logrotate \
					  docker-logrotate \
					  docker-engine
	sudo yum install -y yum-utils \
	  device-mapper-persistent-data \
	  lvm2
	sudo yum-config-manager \
		--add-repo \
		https://download.docker.com/linux/centos/docker-ce.repo
	sudo yum install -y docker-ce docker-ce-cli containerd.io

	sudo curl -L "https://github.com/docker/compose/releases/download/1.24.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
	chmod +x /usr/local/bin/docker-compose
		
}


#### MASTER FUNCTIONS ####
set_master_node(){
	# Hostname & keys & ntp & basic packages
	echo "if$host" > /etc/hostname
	sysctl -w kernel.hostname=if$host

	ssh-keygen -t dsa -f ~/.ssh/id_dsa -N ""
	cp ~/.ssh/id_dsa.pub ~/.ssh/authorized_keys

	### DRBD
	# Enable services
	systemctl enable --now linstor-controller
	sleep 5
	#~ cp ../_data/linstor-client.conf /etc/linstor/
	systemctl enable --now linstor-satellite
	sleep 5
	
	# Create node & resources
	linstor node create if$host 172.31.1.1$host
	linstor storage-pool create lvm if$host data drbdpool
	linstor resource-definition create isard
	linstor volume-definition create isard 470M
	linstor resource create isard --auto-place 1 --storage-pool data
	sleep 5

	# Create filesystem
	mkfs.ext4 /dev/drbd/by-res/isard/0

	## LINSTORDB STORAGE
	# Linstor saves it's data in /var/lib/linstor. In order to have this
	# data HA we should create a new resource that will be held by pcs
	# as a Master/Slave, not as a drbd9 one.
	linstor resource-definition create linstordb
	linstor volume-definition create linstordb 250M
	linstor resource create linstordb --auto-place 1 --storage-pool data
	systemctl disable --now linstor-controller
	rsync -avp /var/lib/linstor /tmp/
	mkfs.ext4 /dev/drbd/by-res/linstordb/0
	rm -rf /var/lib/linstor/*
	mount /dev/drbd/by-res/linstordb/0 /var/lib/linstor
	rsync -avp /tmp/linstor/ /var/lib/linstor/
	
	### PACEMAKER
	# Add host & start cluster
	usermod --password $(echo isard-flock | openssl passwd -1 -stdin) hacluster
	pcs cluster auth if$host <<EOF
hacluster
isard-flock
EOF
	pcs cluster setup --name isard if$host
	pcs cluster enable
	pcs cluster start if$host

	# Stonith 
	#pcs stonith create stonith-rsa-if1 fence_rsa action=off ipaddr="if1" login=root pcmk_host_list=if1 secure=true
	pcs property set stonith-enabled=false
	
	# Linstordb Master/Slave & linstor controller
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

	# Cluster needed policy
	pcs property set no-quorum-policy=ignore

	# Isard storage & nfs exports
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

	# Isard floating IP
	pcs resource create isard-ip ocf:heartbeat:IPaddr2 ip=172.31.0.1 cidr_netmask=32 nic=nas:0  op monitor interval=30 

	# Group and constraints
	pcs resource group add server linstordb-fs linstor-controller isard_fs nfs-daemon nfs-root isard_data isard-ip
	pcs constraint order set linstordb-fs linstor-controller isard_fs nfs-daemon nfs-root isard_data isard-ip

	## NFS client nodes configuration (should avoid isard nfs server colocation)
	pcs resource create nfs-client Filesystem \
			device=isard-nas:/isard directory="/opt/isard" \
			fstype="nfs" "options=defaults,noatime" op monitor interval=10s
	pcs resource clone nfs-client clone-max=8 clone-node-max=8 notify=true
	pcs constraint colocation add nfs-client-clone with isard-ip -INFINITY
		
	### This cron will monitor for new nodes (isard-new) and lauch auto config
	cp ./resources/cron-isard-new.sh /root
	chmod a+x /root/cron-isard-new.sh
	cp ./resources/cron-isard-new /etc/cron.d/	
}

##########################

scp ./resources/hosts /etc/hosts
install_base_pkg

if [[ $master_node == -1 ]]; then
	dialog --title "Maste node" \
	--backtitle "Is this the first (master) node?" \
	--yesno "Set up as MASTER node?" 7 60
	if [[ $? == 0 ]] ; then
		master_node=1
		host=1
	else
		master_node=0
		host=254 # Isard new
	fi
fi

remove_all_if
get_ifs

# STORAGE
devs=($(lsblk -d -n -oNAME,RO | grep '0$' | awk '!/sr0/' | awk {'print $1'}))
if [[ ${#devs[@]} -gt 2 ]]; then
	# secondary master
	set_viewers_if
	set_internet_if
	set_drbd_if
	set_nas_if

	set_storage
	set_pacemaker
	set_docker
	if [[ $master_node == 1 ]]; then
		set_master_node
	fi
fi
if [[ ${#devs[@]} -eq 2 ]]; then
	# replica
	set_viewers_if
	set_internet_if
	set_drbd_if
	set_nas_if
	
	set_storage
	set_pacemaker
	set_docker
	if [[ $master_node == 1 ]]; then
		set_master_node
	fi
fi
if [[ ${#devs[@]} -eq 1 ]]; then
	# diskless
	set_viewers_if
	set_internet_if
	set_nas_if

	set_pacemaker
fi














