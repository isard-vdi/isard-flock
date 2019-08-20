# PACEMAKER CLUSTER KVM LAB

The script will create a full lab to test behaviour of constraints and
fencing in our cluster.

The first node (if1) will have a raid.
The first three nodes will have storage and thus a drbd setup. Also they
will have drbd network (with MTU 9000). Any of them could be the node
that starts the drbd mountpoint and nfs export to others.
The rest of the nodes (>3) will not have storage so they will behave
only as a nfs clients that will mount the exported drbd filesystem.

So we will have one node with filesystem mounted and exported and all the
others will mount it as nfs clients.

To have a full working cluster we should have stonith. To simulate stonith
with the fence_espurna we need another VM, the stonith one that will run
a Flask api that simulates espurna API and bridges requests to the host
virsh to create/destroy VMs.

## Set up

1. Create a gold image disk and install Centos 7.0:
	qemu-img create -f qcow2 /var/lib/libvirt/images/centos7.qcow2 10G
2. Create the cluster VM. Set the number of nodes to create i.e. 4
	./create_cluster.sh <number of nodes>
3. Start stonith VM and create keys and copy it to host (libvirt access)
	ssh-keygen
	ssh-copy-id root@192.168.122.1
	(NOTE: Check on host the firewalld, sshd and selinux!)
3. Start cluster nodes in order. Wait at least five minutes between node
	start. Monitor pcs status on node if1 till it is online and repeat
	process for other nodes in order.
	
Use '0123456789ABCDEF' as espurna stonith apikey
