# ISARD FLOCK - MASTER NODE

The master node will have:

- ssd for the OS
- raid 1 of nvme
- 2x 1GB (viewers and internet)
- 2x 10GB (nas and drbd)

## Install
- OS: CentOS 7 minimal

/etc/hosts

```
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

/etc/udev/rules.d/70-persistent-net.rules

```
SUBSYSTEM=="net", ACTION=="add", DRIVERS=="?*", ATTR{address}=="0c:c4:7a:aa:aa:aa", ATTR{type}=="1", KERNEL=="e*", NAME="viewers"
SUBSYSTEM=="net", ACTION=="add", DRIVERS=="?*", ATTR{address}=="0c:c4:7a:aa:aa:ab", ATTR{type}=="1", KERNEL=="e*", NAME="internet"
SUBSYSTEM=="net", ACTION=="add", DRIVERS=="?*", ATTR{address}=="0c:c4:7a:aa:aa:ac", ATTR{type}=="1", KERNEL=="e*", ATTR{mtu}="9000", NAME="nas"
SUBSYSTEM=="net", ACTION=="add", DRIVERS=="?*", ATTR{address}=="0c:c4:7a:aa:aa:ad", ATTR{type}=="1", KERNEL=="e*", ATTR{mtu}="9000", NAME="drbd"
```

/etc/sysconfig/network-scripts/ifcfg-...

- viewers: in-promise accessible IP
- internet: dhclient
- nas: 172.31.0.11
- drbd: 172.31.1.11

```bash
# BASE PACKAGES NEEDED
yum update
yum install -y curl wget git epel-release lvm2 java-1.8.0-openjdk

# GENERAL SERVICES CONFIG
echo "isardflock1" > /etc/hostname
systemctl disable --now firewalld
sed -i s/^SELINUX=.*$/SELINUX=disabled/ /etc/selinux/config && setenforce 0

# SSH KEYS WITHOUT PWD
ssh-keygen -t dsa -f ~/.ssh/id_dsa -N ""
cp ~/.ssh/id_dsa.pub ~/.ssh/authorized_keys
(scp -r ~/.ssh ic2-cluster:)

# RAID & DRBD VOLUME GROUP
mdadm --create --verbose /dev/md0 --level=1 --raid-devices=2 /dev/nvme0n1 /dev/nvme1n1
sudo mdadm --detail --scan | sudo tee -a /etc/mdadm/mdadm.conf
pvcreate /dev/md0
vgcreate drbdpool /dev/md0

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
```
