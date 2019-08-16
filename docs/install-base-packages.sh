rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
yum install -y https://www.elrepo.org/elrepo-release-7.0-3.el7.elrepo.noarch.rpm
yum install -y nano git sshpass rsync mdadm lvm2 nc dialog
yum install -y kmod-drbd90 drbd90-utils java-1.8.0-openjdk
yum install -y corosync pacemaker pcs python-pycurl python-requests # python-requests needed for fence_espurna
yum install -y nfs-utils

# Only for stonith development
#~ yum install -y python-flask libvirt-python
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

cp hosts /etc/hosts
