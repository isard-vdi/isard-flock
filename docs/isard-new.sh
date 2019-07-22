# Incorporate new node to cluster

- Diskless nodes: Need to join pacemaker
- Storage nodes: Need to join drbd and pacemaker

We will start with a minimum of:

- One linstor-controller with drbd isard-storage shared
- One pacemaker node in cluster

CONSIDERATIONS
1) linstor-controller and nfs-server can run only where storage present
- Linstor-controller and nfs-server will be only installed on storage nodes

2) Linstor-satellite will run in all the storage nodes
- Linstor-satellite will be installed on all storage nodes

3) We will use colocation -INFINITY to exclude satellite from controller nodes

4) Satellite and diskless nodes will mount storage through nfs

5) Isard will start with linstor-controller and nfs-server node

INSTALLED PACKAGES
- MASTER: pacemaker linstor-controller linstor-satellite  nfs-server docker isard
    Has vg data and raid md0
REPLICA: pacemaker (linstor-controller) linstor-satellite (nfs-server) docker isard-hypervisor
    Has vg data
DISKLESS: pacemaker docker isard-hypervisor
    Does not have vg data
GVT-D: KERNEL5 pacemaker docker isard-gvt-hypervisor
	Does have i915_gvt in /sys/...
AMDGPU: pacemaker docker isard-amdgpu-hypervisor
	Does have a Firepro
GVT-D REPLICA: pacemaker (linstor-controller) linstor-satellite (nfs-server) docker isard-gvt-hypervisor
    Has i915 and vg data
AMDGPU REPLICA: pacemaker (linstor-controller) linstor-satellite (nfs-server) docker isard-amdgpu-hypervisor
    Has Firepro and vg data
BACKUP: pacemaker docker-hypervisor backupninja
    Has vg backup
    
HOW WE DECIDE TO START isard-hypervisor/isard-gvt-hypervisor/isard-amdgpu-hypervisor?
We can just copy the correct file with isard-hypervisor name

ADD NODE
linstor-controller node should monitor for new nodes on 172.31.0.254

# SYSTEM DEPLOYMENT
yum update
yum install -y curl wget git epel-release lvm2 java-1.8.0-openjdk
mdadm --create --verbose /dev/md0 --level=1 --raid-devices=2 /dev/nvme0n1 /dev/nvme1n1
sudo mdadm --detail --scan | sudo tee -a /etc/mdadm/mdadm.conf
pvcreate /dev/md0
vgcreate drbdpool /dev/md0

# SCRIPT TO MONITOR AND RUN
#!/bin/bash

# Get next hostname
hostn=1
while nc -z "ic$hostn-cluster" 22 2>/dev/null; do
  hostn=$((hostn+1))
done

# Copy keys
scp -r ~/.ssh isard-new:

# Set correct IPs
ssh ic$hostn-cluster -- sed -i s/^IPADDR=.*$/IPADDR="172.31.0.1$hostn"/ /etc/system/network-interfaces/ifcfg-nas
ssh ic$hostn-cluster -- sed -i s/^IPADDR=.*$/IPADDR="172.30.0.1$hostn"/ /etc/system/network-interfaces/ifcfg-drbd
## set viewers address?
## set internet address?

# Operations
ssh ic$hostn-cluster -- echo "isardcluster$hostn" > /etc/hostname
scp /etc/hosts ic$hostn-cluster:/etc/hosts
ssh ic$hostn-cluster -- mkdir /opt/packages
scp /opt/packages/* ic$hostn-cluster:/opt/packages
ssh ic$hostn-cluster -- 
ssh ic$hostn-cluster -- 
ssh ic$hostn-cluster -- 


echo "isardflock1" > /etc/hostname
systemctl disable --now firewalld
sed -i s/^SELINUX=.*$/SELINUX=disabled/ /etc/selinux/config && setenforce 0

# SSH KEYS WITHOUT PWD
ssh-keygen -t dsa -f ~/.ssh/id_dsa -N ""
cp ~/.ssh/id_dsa.pub ~/.ssh/authorized_keys
(scp -r ~/.ssh ic2-cluster:)

# RAID & DRBD VOLUME GROUP


# DRBD (controller + satellite)
rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
yum install https://www.elrepo.org/elrepo-release-7.0-3.el7.elrepo.noarch.rpm
yum install kmod-drbd90 drbd90-utils

git clone https://github.com/isard-vdi/isard-flock && cd isard-flock
cd linstor
rpm -ivh linstor-common-0.9.12-1.el7.noarch.rpm  linstor-controller-0.9.12-1.el7.noarch.rpm  linstor-satellite-0.9.12-1.el7.noarch.rpm python-linstor-0.9.8-1.noarch.rpm
rpm -ivh rpm -ivh linstor-client-0.9.8-1.noarch.rpm
cd ..
systemctl enable --now linstor-controller
linstor node create isardflock1 172.31.1.11
systemctl enable --now linstor-satellite

linstor storage-pool create lvm isardflock1 data drbdpool
linstor resource-definition create isard
linstor volume-definition create isard 470G
linstor resource create isard --auto-place 1 --storage-pool data
mkfs.ext4 /dev/drbd1000
mkdir /opt/isard
mount /dev/drbd1000 /opt/isard (till we have pacemaker HA)

# PACEMAKER
yum install -y corosync pacemaker pcs python-pycurl fence-agents-apc fence-agents-apc-snmp
systemctl enable pcsd
systemctl enable corosync
systemctl enable pacemaker
systemctl start pcsd
passwd hacluster
pcs cluster auth ic1-cluster
pcs cluster setup --name isard ic1-cluster
pcs cluster enable
pcs cluster start ic1-cluster

# DOCKER & Isard
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

rpm -ivh linstor/linstor-docker-volume-0.2.0-1.noarch.rpm
systemctl enable --now linstor-docker-volume.socket
systemctl enable --now linstor-docker-volume.service

cp docker/docker-compose.yml /opt/isard
cd /opt/isard
docker-compose up -d
