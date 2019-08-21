#!/bin/bash

## yum install -y libguestfs-tools-c

destroy_previous(){
	n=0
	while [[ $? == 0 ]];
	do
		n=$((n+1))
		virsh destroy if$n
		virsh undefine if$n
	done
}

init_cluster(){
	virsh destroy stonith
	virsh undefine stonith
	destroy_previous
	
	# simulate 10G 9000MTU networks
	virsh net-define nas-net.xml
	virsh autostart nas
	virsh net-define drbd-net.xml
	virsh autostart drbd

	rm -rf /var/lib/libvirt/images/if*

	virsh destroy stonith
	virsh undefine stonith
	qemu-img create -b /var/lib/libvirt/images/centos7.qcow2 -f qcow2 /var/lib/libvirt/images/stonith.qcow2
	virt-install --name=stonith \
	--vcpus=2 \
	--memory=1024 \
	--boot hd \
	--disk path=/var/lib/libvirt/images/stonith.qcow2,format=qcow2 \
	--network network=default \
	--network network=nas \
	--os-type=linux \
	--os-variant=centos7.0

	virsh destroy stonith
	virt-copy-in -d stonith ../../isard-flock /opt/
	virt-copy-in -d stonith ./espurna_virsh_emulator.service /etc/systemd/system/multi-user.target.wants/
	#~ virt-copy-in -d stonith /root/.ssh/* /opt/
}

create_node(){
	master="0"
	if [[ $i == 1 ]]; then
		master="1"
	fi
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

if [[ -z "$1" ]] || [[ -z "$2" ]]; then
	echo "You must pass at least two arguments:"
	echo "./create-nodes.sh [init_cluster] [raid|disk|diskless]"
	echo "ALERT: The first one you create should be master"
	exit 1
fi

i=1
for node in "$@" 
do
echo "$node"
	if [[ $i == 1 ]]; then
		if [[ "$node" == "diskless" ]]; then
			echo "First node can't be diskless. Choose init_cluster, raid or disk node type"
			exit 1
		fi
		if [[ "$node" == "init_cluster" ]]; then
			init_cluster
			continue
		else
			destroy_previous
		fi
	fi
	create_node
	i=$((i+1))
done
