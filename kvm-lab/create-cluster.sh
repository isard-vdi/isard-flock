#!/bin/bash

## yum install -y libguestfs-tools-c

if ! [[ -e /var/lib/libvirt/images/centos7.qcow2 ]]; then
	echo "There is no base centos VM installed on /var/lib/libvirt/images/centos7.qcow2 !!"
	echo "Please create a clean centos 7 install in that file before creating cluster"
	echo "NOTE: Better create that VM with isard-flock-iso repo"
	exit 1
fi

if [[ -z "$1" ]]; then
	echo "You must pass as argument how many nodes will have the cluster!"
	echo "For example: ./create-cluster.sh 4"
	exit 1
fi

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
				
for ((i=1; i<=$1; i++)); do
	virsh destroy if$i
	virsh undefine if$i
	if [[ $i == 1 ]]; then
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
		sed "s/ExecStart=.*/ExecStart=/usr/bin/bash -c '/opt/auto-install.sh --master 1 --if_viewers eth0 --if_nas eth1 --if_drbd eth2 --raid_level 1 --raid_devices /dev/vdb,/dev/vdc --pv_device /dev/md0 --espurna_fencing 1 --espurna_apikey 0123456789ABCDEF 1>/tmp/auto-install.log 2>/tmp/auto-install-error.log'" auto-install.service
		virt-copy-in -d if$i ../install-isard-flock.sh /opt/auto-install.sh
		virt-copy-in -d if$i ./auto-install.service /etc/systemd/system/multi-user.target.wants/
	fi
	if [[ $i == 2 ]] || [[ $i == 3 ]]; then
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
		sed "s/ExecStart=.*/ExecStart=/usr/bin/bash -c '/opt/auto-install.sh --master 0 --if_viewers eth0 --if_nas eth1 --if_drbd eth2 1>/tmp/auto-install.log 2>/tmp/auto-install-error.log'" auto-install.service
		virt-copy-in -d if$i ../install-isard-flock.sh /opt/auto-install.sh		
		virt-copy-in -d if$i ./auto-install.service /etc/systemd/system/multi-user.target.wants/
	fi
	if [[ $i > 3 ]]; then
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
		sed "s/ExecStart=.*/ExecStart=/usr/bin/bash -c '/opt/auto-install.sh --master 0 --if_viewers eth0 --if_nas eth1 1>/tmp/auto-install.log 2>/tmp/auto-install-error.log'" auto-install.service
		virt-copy-in -d if$i ../install-isard-flock.sh /opt/auto-install.sh	
		virt-copy-in -d if$i ./auto-install.service /etc/systemd/system/multi-user.target.wants/
	fi
done
