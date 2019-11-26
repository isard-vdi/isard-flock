# PACEMAKER CLUSTER KVM LAB

There are three scripts:
- create-cluster.sh: You need to provide a number of nodes to create as
    a parameter.
    - The first node (if1) will have a raid.
    - The first three nodes will have storage and thus a drbd setup. Also they
        will have drbd network (with MTU 9000). Any of them could be the node
        that starts the drbd mountpoint and nfs export to others.
    - The rest of the nodes (>3) will not have storage so they will behave
        only as a nfs clients that will mount the exported drbd filesystem.

- create-nodes.sh: You need to provide **init_cluster** as first parameter
    the first time and after the parameters **raid**, **disk** or **diskless**
    for every node you want to create.
    The init_cluster will set up nas and drbd networking in KVM and create
    the stonith emulation VM.
    The rest of the parameters will define machines with **raid**, with
    only a **disk** for data or **diskless**.
    
- add-node.sh: You need to provide the parameters **raid**, **disk** or **diskless**
    for the node to be added to the existing cluster.
    
NOTE: You can set a maximum of 8 nodes for this lab.

## How it works
We need at least one node with storage (raid or disk) and a stonith VM.
The first node created will be the master one in the cluster. This means
that will have a cron that will adopt new nodes as they are started and
configured.
Configuration for all nodes created is done automatically with a systemd
service at the first boot and removed after have been set up.
The password used for root and pacemaker cluster is isard-flock

## Steps to bring it up

1. Create a gold image disk and install Centos 7.0:
    qemu-img create -f qcow2 /var/lib/libvirt/images/centos7.qcow2 10G
2. Create the cluster VM. You can use the create_cluster.sh:
    ./create-cluster.sh <number of nodes>
    or
    ./create-nodes.sh init_cluster [raid|disk] [raid|disk|diskless] ...
    afterwards you can add new nodes:
    ./add-node.sh [raid|disk|diskless]
3. First VM to start is stonith VM and create keys and copy it to host 
    (libvirt access):
    ssh-keygen
    ssh-copy-id root@192.168.122.1
    (NOTE: Check on host the firewalld, sshd and selinux!)
4. When a node starts it will install and configure itself. You will see
    some messages in console and you can see if the first boot installation
    script has finished by looking for the file /.installing. When it
    disappeares you can work with the node or wait for new ones to be
    started
5. Start cluster nodes in order. Wait at least five minutes between node
    start. Monitor pcs status on node if1 till it is online and repeat
    process for other nodes in order.
    
Use '0123456789ABCDEF' as espurna stonith apikey if needed.


## Final notes

The lab will allow you to see how it behaves when a node fails or when a
node is added to the cluster.
Also is interesting to change cluster constraints/resources and see how
it behaves with new configuration.
It was initially intended to setup a lab to adjust pacemaker cluster for
IsardVDI virtualization cluster with automated deployment.
