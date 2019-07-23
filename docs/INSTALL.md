# ISARD FLOCK

X = Cube number

## Install
- OS: CentOS 7

```bash
yum update
yum install curl nano wget epel-release
yum install iotop htop iftop glances
```

## General configuration

```
/etc/hostname -> isardcubeX
systemctl disable --now firewalld
sed -i s/^SELINUX=.*$/SELINUX=disabled/ /etc/selinux/config
```

Note for production (selinux & firewalld should be set)

- The linstor-satellite requires ports 3366 and 3367. The linstor-controller requires ports 3376 and 3377. Make sure you have these ports allowed on your firewall. 

## Network configuration

Minimum configuration should have a gigabit ethernet and a 10G. In that scenario the gigabit will be the **viewers** and the 10G will hold **both nas and drbd** ips. But ideally we will have a server with 2 gigabit and 2 10gigabit:

- Gigabit
  - viewers: (default route) 10.1.171.1X/24
  - internet: 10.1.170.1X/24

- 10G
  - nas: 172.31.0.1X/24
  - drbd: 172.31.1.1X/24

For convenience we will set those interface names in udev /etc/udev/rules.d/70-persistent-net.rules:

```bash
SUBSYSTEM=="net", ACTION=="add", DRIVERS=="?*", ATTR{address}=="0c:c4:7a:aa:aa:aa", ATTR{type}=="1", KERNEL=="e*", NAME="viewers"
SUBSYSTEM=="net", ACTION=="add", DRIVERS=="?*", ATTR{address}=="0c:c4:7a:aa:aa:ab", ATTR{type}=="1", KERNEL=="e*", NAME="internet"
SUBSYSTEM=="net", ACTION=="add", DRIVERS=="?*", ATTR{address}=="0c:c4:7a:aa:aa:ac", ATTR{type}=="1", KERNEL=="e*", ATTR{mtu}="9000", NAME="nas"
SUBSYSTEM=="net", ACTION=="add", DRIVERS=="?*", ATTR{address}=="0c:c4:7a:aa:aa:ad", ATTR{type}=="1", KERNEL=="e*", ATTR{mtu}="9000", NAME="drbd"
```

And we will set IPs in config scripts /etc/sysconfig/network-scripts:

```bash
[root@isardcube2 network-scripts]# ls
ifcfg-drbd      ifcfg-viewers  ifdown-ippp  ifdown-ppp     ifdown-TeamPort  ifup-bnep  ifup-isdn   ifup-ppp     ifup-TeamPort     network-functions
ifcfg-internet  ifdown         ifdown-ipv6  ifdown-routes  ifdown-tunnel    ifup-eth   ifup-plip   ifup-routes  ifup-tunnel       network-functions-ipv6
ifcfg-lo        ifdown-bnep    ifdown-isdn  ifdown-sit     ifup             ifup-ippp  ifup-plusb  ifup-sit     ifup-wireless
ifcfg-nas       ifdown-eth     ifdown-post  ifdown-Team    ifup-aliases     ifup-ipv6  ifup-post   ifup-Team    init.ipv6-global
[root@isardcube2 network-scripts]# cat ifcfg-nas
TYPE="Ethernet"
PROXY_METHOD="none"
BROWSER_ONLY="no"
BOOTPROTO="none"
DEFROUTE="no"
IPV4_FAILURE_FATAL="no"
IPV6INIT="no"
NAME="nas"
DEVICE="nas"
ONBOOT="yes"
IPADDR="172.31.0.12"
PREFIX="24"
```

Remember:

- If only one gigabit available it should be viewers. Only one ip will be needed, the viewers one. 
- If only one 10g available it will hold both nas and drbd ip

### 10G optimization

TODO

## Firewalld & selinux

TODO

## HOSTS & KEYS

We will set hosname as **isardcubeX** where X is the server number.

We will set drbd hostnames:

```bash
[root@isardcube2 network-scripts]# cat /etc/hosts
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
172.31.1.11 ic1-cluster
172.31.1.12 ic2-cluster
172.31.1.13 ic3-cluster
172.31.1.14 ic4-cluster
172.31.1.15 ic5-cluster
172.31.1.16 ic6-cluster
172.31.1.17 ic7-cluster
172.31.1.18 ic8-cluster

172.31.0.1 isard-nas
172.31.0.254 isard-new

```

And we will create a new *DSA* key and share it along the cluster:

```bash
ssh-keygen -t dsa -f ~/.ssh/id_dsa -N ""
cp ~/.ssh/id_dsa.pub ~/.ssh/authorized_keys
scp -r ~/.ssh ic2-cluster:
scp -r ~/.ssh ic3-cluster:
ssh ic2-cluster -- uname -n
ssh ic3-cluster -- uname -n
```

NOTE: You should check twice that you are able to run commands (linke the uname -n) to other servers in the cluster before setting drbd or pacemaker.

## RAID & PV/VG

```bash
mdadm --create --verbose /dev/md0 --level=1 --raid-devices=2 /dev/nvme0n1 /dev/nvme1n1
sudo mdadm --detail --scan | sudo tee -a /etc/mdadm/mdadm.conf

yum install lvm2 -y
pvcreate /dev/md0
vgcreate drbdpool /dev/md0
```

This should be done in all the nodes with storage

## DRBD & LINSTOR
A LINSTOR setup requires at least one active controller and one or more satellites.

- Controller: deployed as an HA resource with pacemaker
- Satellite: runs in all nodes that needs the storage

- Client: Utilities

The controller should be started with pacemaker in HA and all nodes with storage will start also as satellites (acces to drbd data)

### Epel repository

Add epel repo and install drbd kernel module and utils:

```bash
rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
yum install https://www.elrepo.org/elrepo-release-7.0-3.el7.elrepo.noarch.rpm
yum install kmod-drbd90 drbd90-utils
```

Reboot maybe needed at this stage

yum install git

### DRBDMANAGE

```bash
git clone https://github.com/LINBIT/drbdmanage
cd drbdmanage
yum install pygobject2 help2man wget libxslt
cat install_rpm.txt | sh
make
make install
systemctl status drbdmanaged
systemctl enable drbdmanaged
```

### LINSTOR-SERVER (controller and satellite)

We first install gradle as linstor-server is a java app

```bash
yum install java-1.8.0-openjdk java-1.8.0-openjdk-devel rpm-build
curl -s get.sdkman.io | bash
source "$HOME/.sdkman/bin/sdkman-init.sh"
sdk install gradle
exit & login again (to apply .bashrc modifications for gradle path)
```

Now we will create rpm for linstor-server and install it:

```bash
wget https://www.linbit.com/downloads/linstor/linstor-server-0.9.12.tar.gz
rpmbuild -tb linstor-server-0.9.12.tar.gz
rpm -ivh /root/rpmbuild/RPMS/noarch/*
```

If we only want to install the precompiled packages in **another machine in the cluster**:

```bash
scp ic1-cluster:/root/rpmbuild/RPMS/noarch/* .
yum install java-1.8.0-openjdk lvm2 -y
rpm -ivh *
systemctl enable --now linstor-satellite (if the node has storage)

scp ic1-cluster:/root/linstor/linstor-client-0.9.8/dist/linstor-client-0.9.8-1.noarch.rpm .
scp ic1-cluster:/root/linstor/python-linstor-0.9.8/dist/python-linstor-0.9.8-1.noarch.rpm .
rpm -ivh python-linstor-0.9.8-1.noarch.rpm
rpm -ivh linstor-client-0.9.8-1.noarch.rpm

pcs cluster add ic4-cluster (after installing pacemaker)
pcs cluster start ic4-cluster

pcs cluster enable (in ic4-cluster, this will start pacemaker in every reboot)

In ic1-cluster:
linstor node create isardcube4 172.31.1.14
linstor storage-pool create lvm isardcube4 data drbdpool
linstor resource create isard --auto-place 3 --storage-pool data
```

**IMPORTANT**

Linstor-satellite does remove all resources found in /var/lib/linstor.d as it hopes that they will be populated again when the linstor-controller contacts it again. If the linstor-controller is no available no resources will be up.

So if we miss the controller the won't be any drbd resources. One workaround is to modify linstor-satellite.service and add --keep-res isard at the ExecStart line:

```bash
ExecStart=/usr/share/linstor-server/bin/Satellite --logs=/var/log/linstor-satellite --config-directory=/etc/linstor --keep-res isard
```

And this should be done in all the nodes.

### LINSTOR-CLIENT

Linstor client should be installed in all nodes that can be a controller. Remember that the controller will be set in a node (that has storage) in HA by pacemaker. 

```bash
wget https://www.linbit.com/downloads/linstor/python-linstor-0.9.8.tar.gz
tar xvf python-linstor-0.9.8.tar.gz
yum install python-setuptools rpm-build
cd python-linstor-0.9.8
make rpm
rpm -ivh dist/python-linstor-0.9.8-1.noarch.rpm

wget https://www.linbit.com/downloads/linstor/linstor-client-0.9.8.tar.gz
tar xvf linstor-client-0.9.8.tar.gz
cd linstor-client-0.9.8
make rpm
rpm -ivh dist/linstor-client-0.9.8-1.noarch.rpm
```



## SET NODES USING LINSTOR
We do this manually. Afterwards the pacemaker will start the systemd for linstor-controller.

```bash
systemctl enable --now linstor-controller
linstor node create isardcube1 172.31.1.11
linstor node list
```

NOTE: node name must match uname -n. The ip should have the certs copied between nodes!

The node will show as offline because it is missing the linstor-satellite

```bash
systemctl enable --now linstor-satellite
```

Now add other nodes and start there linstor-satellite there

Create **storage pools** and add **resources** and **volumes**

```bash
linstor storage-pool create lvm isardcube1 data drbdpool
linstor storage-pool list
```

Do create the storage-pool in all the nodes with storage:

```bash
[root@isardcube1 ~]# linstor storage-pool create lvm isardcube2 data drbdpool
SUCCESS:
Description:
    New storage pool 'data' on node 'isardcube2' registered.
Details:
    Storage pool 'data' on node 'isardcube2' UUID is: 0c1e0965-4f58-438e-b00a-8e4177230470
SUCCESS:
    (isardcube2) Changes applied to storage pool 'data'
[root@isardcube1 ~]# linstor storage-pool list
╭─────────────────────────────────────────────────────────────────────────────────────────────────────────╮
┊ StoragePool ┊ Node       ┊ Driver ┊ PoolName ┊ FreeCapacity ┊ TotalCapacity ┊ SupportsSnapshots ┊ State ┊
╞┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄╡
┊ data        ┊ isardcube1 ┊ LVM    ┊ drbdpool ┊   931.38 GiB ┊    931.38 GiB ┊ false             ┊ Ok    ┊
┊ data        ┊ isardcube2 ┊ LVM    ┊ drbdpool ┊   476.94 GiB ┊    476.94 GiB ┊ false             ┊ Ok    ┊
╰─────────────────────────────────────────────────────────────────────────────────────────────────────────╯
```

Now create **resources**, **volumes** and deploy them to nodes:

```bash
linstor resource-definition create isard
linstor volume-definition create isard 476G

linstor resource create isard --auto-place 2 --storage-pool data
```

NOTE: It will fail if not enough nodes available

Now mount it in a node and create filesystem:

```bash
mkdir /opt/isard
mkfs.ext4 /dev/drbd/by-res/isard/0
mount /dev/drbd/by-res/isard/0 /opt/isard
```

REFERENCES:

https://docs.google.com/document/d/1RRRL3lrUeQYEeE5GVVrvuLI_na9ToPRo3bmq0eu2HKI/edit#

https://www.sraoss.co.jp/tech-blog/drbd/drbd9-linstor/

https://github.com/LINBIT/linbit-documentation/blob/master/UG9/en/administration-linstor.adoc
API: https://app.swaggerhub.com/apis-docs/Linstor/Linstor/1.0.5

### DRBD Optimizations

```
linstor controller drbd-options -h
linstor resource-definition drbd-options -h
linstor volume-definition drbd-options -h
linstor resource drbd-peer-options -h
```

TODO

### Deleting things

```
linstor resource delete isardcube2 isardcube1 isard
linstor volume-definition set-size isard 0 450G
linstor resource create isard --auto-place 2 --storage-pool data
mkfs.ext4 /dev/drbd/by-res/isard/0
```

### Growing ext4

```
linstor volume-definition set-size isard 0 470G
e2fsck -f /dev/drbd/by-res/isard/0
resize2fs /dev/drbd/by-res/isard/0
```

## Docker & Isard

We will be setting isard in /opt/isard/src as it will be set in the drbd volume and thus will be in HA by pacemaker.

All nodes with storage should install docker & docker-compose

```
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
```



## PACEMAKER

The live migration of docker containers is not trivial at all. It is not the same as migrating a fully virtualized vm. Things to consider:

- All /var/lib/docker should be shared?
- We should pause, migrate and then resume in the other host the container: https://github.com/stmuraka/container-migration/blob/master/Examples/migrateExample.sh
- https://github.com/portainer/portainer/issues/2572

Install pacemaker and enable services

```bash
yum install -y corosync pacemaker pcs python-pycurl fence-agents-apc fence-agents-apc-snmp
systemctl enable pcsd
systemctl enable corosync
systemctl enable pacemaker
systemctl start pcsd
reboot (maybe better)
```

Create hacluster user for pacemaker:

```bash
passwd hacluster
```

Auth and add nodes

```
[root@isardcube1 ~]# pcs cluster auth ic1-cluster ic2-cluster
Username: hacluster
Password: 
ic2-cluster: Authorized
ic1-cluster: Authorized
[root@isardcube1 ~]# pcs status
Error: cluster is not currently running on this node
[root@isardcube1 ~]# pcs cluster setup --name isard ic1-cluster ic2-cluster
Destroying cluster on nodes: ic1-cluster, ic2-cluster...
ic1-cluster: Stopping Cluster (pacemaker)...
ic2-cluster: Stopping Cluster (pacemaker)...
ic1-cluster: Successfully destroyed cluster
ic2-cluster: Successfully destroyed cluster

Sending 'pacemaker_remote authkey' to 'ic1-cluster', 'ic2-cluster'
ic1-cluster: successful distribution of the file 'pacemaker_remote authkey'
ic2-cluster: successful distribution of the file 'pacemaker_remote authkey'
Sending cluster config files to the nodes...
ic1-cluster: Succeeded
ic2-cluster: Succeeded

Synchronizing pcsd certificates on nodes ic1-cluster, ic2-cluster...
ic2-cluster: Success
ic1-cluster: Success
Restarting pcsd on the nodes in order to reload the certificates...
ic2-cluster: Success
ic1-cluster: Success
[root@isardcube1 ~]#
```

Start cluster and enable nodes

```bash
pcs cluster start
pcs cluster enable --all
```

```bash
## THIS IS NEEDED FOR HA LINSTOR-CONTROLLER.
## The database should be shared along all the storage nodes that can become a linstor-controller

linstor resource-definition create linstordb
linstor volume-definition create linstordb 250M
linstor resource create linstordb --auto-place 2 --storage-pool data

systemctl stop linstor-controller
rsync -avp /var/lib/linstor /tmp/
mkfs.ext4 /dev/drbd/by-res/linstordb/0
rm -rf /var/lib/linstor/*
mount /dev/drbd/by-res/linstordb/0 /var/lib/linstor
rsync -avp /tmp/linstor/ /var/lib/linstor/

pcs resource create linstordb-drbd ocf:linbit:drbd drbd_resource=linstordb op monitor interval=15s role=Master op monitor interval=30s role=Slave
pcs resource master linstordb-drbd-clone linstordb-drbd master-max=1 master-node-max=1 clone-max=8 clone-node-max=1 notify=true
pcs resource create linstordb-fs Filesystem \
        params device="/dev/drbd/by-res/linstordb/0" directory="/var/lib/linstor" \
        op start interval=0 timeout=60s \
        op stop interval=0 timeout=100s \
        op monitor interval=20s timeout=40s
pcs resource create linstor-controller systemd:linstor-controller \
        op start interval=0 timeout=100s
        op stop interval=0 timeout=100s
        op monitor interval=30s timeout=100s

## NOW THE FILESYSTEM
pcs resource create isard_fs Filesystem device="/dev/drbd/by-res/isard/0" directory="/opt/isard" fstype="ext4" "options=defaults,noatime,nodiratime,noquota" op monitor interval=10s

pcs resource create nfs-daemon systemd:nfs-server \
nfs_shared_infodir=/opt/isard/nfsinfo nfs_no_notify=true op monitor interval=30s
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

pcs resource group add isard-storage linstor-controller isard_fs nfs-daemon nfs-root isard_data isard-ip

pcs constraint order \
	promote linstordb-drbd-clone then isard-storage INFINITY \
	require-all=true symmetrical=true \
	setoptions kind=Mandatory
	
pcs constraint colocation add \
	isard-storage with master linstordb-drbd-clone INFINITY
```



```bash
pcs resource create nfs-mount ocf:heartbeat:Filesystem device="172.31.0.1:/isard" directory="/opt/isard" fstype="nfs"
```

- clone isard-nfs-mount to all except where group isard-storage is running

```
pcs resource clone nfs-mount 
pcs constraint colocation add isard-storage with nfs-mount-clone -INFINITY
```



## Espurna as Stonith

We will be handling espurna plug devices as an stonith for the nodes in the system. 


