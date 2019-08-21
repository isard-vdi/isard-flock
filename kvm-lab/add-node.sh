#!/bin/bash

## yum install -y libguestfs-tools-c

set_node_number(){
	i=0
	while [[ $? == 0 ]];
	do
		i=$((i+1))
		virsh desc if$i 1&>2 /dev/null
	done
}

create_node(){
	master="0"
	if [[ "$node" == "raid" ]]; then
		qemu-img create -b /var/lib/libvirt/images/centos7.qcow2 -f qcow2 /var/lib/libvirt/images/if$i.qcow2
		qemu-img create -f qcow2 /var/lib/libvirt/images/if$i-d1.qcow2 1G
		qemu-img create -f qcow2 /var/lib/libvirt/images/if$i-d2.qcow2 1G

		virt-install --name=if$i \
		--vcpus=2 \
		--memory=1024 \
		--boot hd \
		--disk path=/var/lib/libvirt/images/if$i.qcow2,format=qcow2 \
		--disk path=/var/lib/libvirt/images/if$i-d1.qcow2,format=qcow2 \
		--disk path=/var/lib/libvirt/images/if$i-d2.qcow2,format=qcow2 \
		--network network=default \
		--network network=nas \
		--network network=drbd \
		--os-type=linux \
		--os-variant=centos7.0
		virsh destroy if$i
		virt-copy-in -d if$i ../../isard-flock /opt/
		sed -i "s/^ExecStart=.*/ExecStart=/" auto-install.service
		command="ExecStart=/bin/bash -c 'cd /opt/isard-flock/ \&\& ./install-isard-flock.sh --master $master --if_viewers eth0 --if_nas eth1 --if_drbd eth2 --raid_level 1 --raid_devices /dev/vdb,/dev/vdc --pv_device /dev/md0 --espurna_apikey 0123456789ABCDEF 1>/tmp/auto-install.log 2>/tmp/auto-install-error.log'"
		command_parsed=$(echo "$command" | sed 's_/_\\/_g')
		sed -i "s/^ExecStart=.*/$command_parsed/" auto-install.service
		virt-copy-in -d if$i ./auto-install.service /etc/systemd/system/multi-user.target.wants/
	fi
	if [[ "$node" == "disk" ]]; then
		qemu-img create -b /var/lib/libvirt/images/centos7.qcow2 -f qcow2 /var/lib/libvirt/images/if$i.qcow2
		qemu-img create -f qcow2 /var/lib/libvirt/images/if$i-d1.qcow2 1G

		virt-install --name=if$i \
		--vcpus=2 \
		--memory=1024 \
		--boot hd \
		--disk path=/var/lib/libvirt/images/if$i.qcow2,format=qcow2 \
		--disk path=/var/lib/libvirt/images/if$i-d1.qcow2,format=qcow2 \
		--network network=default \
		--network network=nas \
		--network network=drbd \
		--os-type=linux \
		--os-variant=centos7.0	

		virsh destroy if$i
		virt-copy-in -d if$i ../../isard-flock /opt/
		sed -i "s/^ExecStart=.*/ExecStart=/" auto-install.service
		command="ExecStart=/bin/bash -c 'cd /opt/isard-flock/ \&\& ./install-isard-flock.sh --master $master --if_viewers eth0 --if_nas eth1 --if_drbd eth2 1>/tmp/auto-install.log 2>/tmp/auto-install-error.log'"
		command_parsed=$(echo "$command" | sed 's_/_\\/_g')
		sed -i "s/^ExecStart=.*/$command_parsed/" auto-install.service
		virt-copy-in -d if$i ./auto-install.service /etc/systemd/system/multi-user.target.wants/
	fi
	if [[ "$node" == "diskless" ]]; then
		qemu-img create -b /var/lib/libvirt/images/centos7.qcow2 -f qcow2 /var/lib/libvirt/images/if$i.qcow2
		virt-copy-in -d if$1 ../../isard-flock /opt/
		
		virt-install --name=if$i \
		--vcpus=2 \
		--memory=1024 \
		--boot hd \
		--disk path=/var/lib/libvirt/images/if$i.qcow2,format=qcow2 \
		--network network=default \
		--network network=nas \
		--os-type=linux \
		--os-variant=centos7.0	

		virsh destroy if$i
		virt-copy-in -d if$i ../../isard-flock /opt/
		sed -i "s/^ExecStart=.*/ExecStart=/" auto-install.service
		command="ExecStart=/bin/bash -c 'cd /opt/isard-flock/ \&\& ./install-isard-flock.sh --master 0 --if_viewers eth0 --if_nas eth1 1>/tmp/auto-install.log 2>/tmp/auto-install-error.log'"
		command_parsed=$(echo "$command" | sed 's_/_\\/_g')
		sed -i "s/^ExecStart=.*/$command_parsed/" auto-install.service
		virt-copy-in -d if$i ./auto-install.service /etc/systemd/system/multi-user.target.wants/
	fi
}


if ! [[ -e /var/lib/libvirt/images/centos7.qcow2 ]]; then
	echo "There is no base centos VM installed on /var/lib/libvirt/images/centos7.qcow2 !!"
	echo "Please create a clean centos 7 install in that file before creating cluster"
	echo "NOTE: Better create that VM with isard-flock-iso repo"
	exit 1
fi

if [[ -z "$1" ]]; then
	echo "You must pass one argument:"
	echo "./add-node.sh [raid|disk|diskless]"
	exit 1
fi

set_node_number
node=$1
create_node
