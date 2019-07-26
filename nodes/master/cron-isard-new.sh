#!/bin/bash
# Should be added to cron and will detect and incorporate new nodes
if ping -c 1 isard-new &> /dev/null
then
  echo "Found new isard. Get new host number..."
  host=1
  while nc -z "if$host" 22 2>/dev/null; do
    host=$((host+1))
  done
else
  exit 0
fi

# Copy actual keys to new node
/usr/bin/rsync -ratlz --rsh="/usr/bin/sshpass -p isard-flock ssh -o StrictHostKeyChecking=no -l root" /root/.ssh/*  isard-new:/root/.ssh/

# Copy isard-flock version to new node
#~ scp -r /root/isard-flock isard-new:/root/

# Set new host IP
ssh -n -f isard-new "bash -c 'nohup /root/isard-flock/nodes/others/set_ip.sh $host> /dev/null 2>&1 &'"
while nc -z "if$host" 22 2>/dev/null; do
  sleep 1
done

while ! ping -c 1 172.31.1.1$host &> /dev/null
do
	sleep 2
done
sleep 5

# Check type of node
ssh if$host -- lsblk | grep md
RAID=$?
ssh if$host -- vgs | grep drbdpool
DRBD=$?
ssh if$host -- systemctl status pcsd
PCSD=$?
ssh if$host -- ls /sys/devices/pci0000\:00/0000\:00\:02.0/mdev_supported_types/ | grep i915-GVTg
VGTD=$?
ssh if$host -- vgs | grep backup
BACKUP=$?


# Lauch new node setup

if [[ $DRBD -eq 0 ]]; then
	linstor node add if$host 172.31.1.1$host
	linstor ... auto-place linstordb
	linstor ... auto-place isard
fi
if [[ $PCSD -eq 0 ]]; then
	pcs cluster auth if$host <<EOF
hacluster
isard-flock
EOF
	pcs cluster node add if$host
	pcs cluster start if$host
fi
if [[ $RAID -eq 0 ]]; then
	pcs constraint modify prefer_node_storage add if$host
	# or play with node weights
	
	# wait for /opt/isard to be mounted (drbd or nfs)
	# cd /opt/isard && docker-compose pull
fi
