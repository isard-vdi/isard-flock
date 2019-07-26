#!/bin/bash


#~ 1. MASTER (RAID+DRBD+PACEMAKER+NAS+DOCKER)
#~ 2. REPLICA (DRBD+PACEMAKER+NAS+DOCKER)
#~ 3. DISKLESS (PACEMAKER+NFS)
#~ 4. BACKUP (RAID+NFS)

# Defaults
#~ if_viewers='eth0'
#~ if_internet='eth1'
#~ if_drbd='eth2'
#~ if_nas='eth3'

#~ raid_level=1
#~ raid_devices=(/dev/vdb /dev/vdc)
#~ pv_device="/dev/md0"

install_base_pkg(){
	rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
	yum install -y https://www.elrepo.org/elrepo-release-7.0-3.el7.elrepo.noarch.rpm
	yum install -y nano git sshpass rsync nc dialog
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
		nmcli con add con-name "$new_if" ifname $old_if type ethernet ip4 172.31.$net.254/24
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
	get_ifs
}

set_viewers_if(){
	opt=$(dialog --menu --stdout "Select interface for guests VIEWERS:" 0 0 0 $var )
	if ! [[ $opt -gt ${#interfaces[@]} ]]; then
		old_if=${interfaces[$(($opt-1))]}
		new_if="viewers"
		set_if
	fi
}

set_nas_if(){
	opt=$(dialog --menu --stdout "Select interface for NAS:" 0 0 0 $var )
	if ! [[ $opt -gt ${#interfaces[@]} ]]; then
		old_if=${interfaces[$(($opt-1))]}
		new_if="nas"
		set_if
	fi
}

set_drbd_if(){
	opt=$(dialog --menu --stdout "Select interface for DRBD:" 0 0 0 $var )
	if ! [[ $opt -gt ${#interfaces[@]} ]]; then
		old_if=${interfaces[$(($opt-1))]}
		new_if="drbd"
		set_if
	fi
}

set_internet_if(){
	opt=$(dialog --menu --stdout "Select interface for guests INTERNET:" 0 0 0 $var )
	if ! [[ $opt -gt ${#interfaces[@]} ]]; then
		old_if=${interfaces[$(($opt-1))]}
		new_if="internet"
		set_if
	fi
}

create_raid(){
	yum install -y mdadm
	for d in "${raid_devs[@]}" 
	do
		dd if=/dev/zero of=$d bs=2048 count=4096
	done
	yes | mdadm --create --verbose /dev/md0 --level=$raid_level --raid-devices=${#raid_devs[@]} ${raid_devs[@]}
	sudo mdadm --detail --scan > /etc/mdadm.conf
	pv_device="/dev/md0"
}

create_drbdpool(){
	yum install -y lvm2
	yum install -y kmod-drbd90 drbd90-utils java-1.8.0-openjdk
	pvcreate pv_device
	vgcreate drbdpool pv_device
	cd ../../linstor
	rpm -ivh linstor-common-0.9.12-1.el7.noarch.rpm  linstor-controller-0.9.12-1.el7.noarch.rpm  linstor-satellite-0.9.12-1.el7.noarch.rpm python-linstor-0.9.8-1.noarch.rpm
	rpm -ivh linstor-client-0.9.8-1.noarch.rpm
	cd ../nodes/master
	echo "[global]" > /etc/linstor/linstor-client.conf
	echo "controllers=if1,if2,if3,if4,if5,if6,if7,if8" >> /etc/linstor/linstor-client.conf
	systemctl enable --now linstor-satellite
}

set_storage(){
	var=""
	i=1
	for dev in $devs
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
		echo ${choices[@]}
		pv_device="dev/${devs[0]}"
		echo $pv_device
		#create_drbdpool
	fi
	if [[ ${#devs[@]} -eq 3 ]]; then
		# RAID 1 - 2 DISKS
		cmd=(dialog --separate-output --checklist "Select 2 devices for RAID 1:" 22 76 16)
		options=($var)
		choices=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
		echo ${choices[@]}
		for c in $choices
		do
			raid_sdevs="$raid_sdevs /dev/${devs[$(($c-1))]}"
		done
		raid_devs=(${raid_sdevs[@]})
		raid_level=1
		#create_raid
		#create_drbdpool
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

#### CHECK TYPE OF NODE
# INTERFACES
install_base_pkg
get_ifs

# STORAGE
devs=($(lsblk -d -n -oNAME,RO | grep '0$' | awk {'print $1'}))
if [[ ${#devs[@]} -gt 2 ]]; then
	# secondary master
	set_viewers_if
	set_internet_if
	set_drbd_if
	set_nas_if

	set_raid
	set_drbd
	set_pacemaker
	set_docker
fi
if [[ ${#devs[@]} -eq 2 ]]; then
	# replica
	set_viewers_if
	set_internet_if
	set_drbd_if
	set_nas_if

	set_drbd
	set_pacemaker
	set_docker
fi
if [[ ${#devs[@]} -eq 1 ]]; then
	# diskless
	set_viewers_if
	set_internet_if
	set_nas_if

	set_pacemaker
fi

if [[ $storage -eq 0 ]]; then

fi
exit 1


var=""
i=1
if [[ $? -eq 0 ]]; then
 
fi

exit 1

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

yum install -y sshpass rsync














