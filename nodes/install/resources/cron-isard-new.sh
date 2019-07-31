#!/bin/bash
# Should be added to cron and will detect and incorporate new nodes

# check that cluster is running

# check if new node appears in system or exit
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

# remove keys if known already
sed -i '/^isard-new/ d' /root/.ssh/known_hosts
# Copy actual keys to new node
/usr/bin/rsync -ratlz --rsh="/usr/bin/sshpass -p isard-flock ssh -o StrictHostKeyChecking=no -l root" /root/.ssh/*  isard-new:/root/.ssh/

# Wait for node to finish if it is just installing isard-flock
while ssh isard-new -- ls -lisa / | grep .installing
do
	sleep 5
	echo "Remote host is still installing isard-flock. Waiting..."
done


# Set new host IP's
ssh -n -f isard-new "bash -c 'nohup /root/isard-flock/nodes/install/set_ips.sh $host &'"
# Copy isard-flock version to new node
#~ scp -r /root/isard-flock isard-new:/root/

while ! ping -c 1 172.31.0.1$host &> /dev/null
do
	sleep 2
done
sleep 5

sed -i '/^isard-new/ d' /root/.ssh/known_hosts
/usr/bin/rsync -ratlz --rsh="/usr/bin/sshpass -p isard-flock ssh -o StrictHostKeyChecking=no -l root" /root/.ssh/*  if$host:/root/.ssh/

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

echo "drbd: $DRBD"
echo "pcsd: $PCSD"

# Lauch new node setup

if [[ "$DRBD" == "0" ]]; then
	echo "Setting drbd"
	ssh if$host -- systemctl enable --now linstor-satellite
	sleep 5
	linstor node create if$host 172.31.0.1$host
	linstor storage-pool create lvm if$host data drbdpool
	linstor resource create --storage-pool data if$host isard	
	linstor resource create --storage-pool data if$host linstordb	
fi
if [[ "$PCSD" == "0" ]]; then
	echo "pcsd"
	/sbin/pcs cluster auth if$host <<EOF
hacluster
isard-flock
EOF
	/sbin/pcs cluster node add if$host
	/sbin/pcs cluster start if$host
fi
if [[ $RAID -eq 0 ]]; then
	#~ echo "raid"
	exit 0
	#~ pcs constraint modify prefer_node_storage add if$host
	# or play with node weights
	
	# wait for /opt/isard to be mounted (drbd or nfs)
	# cd /opt/isard && docker-compose pull
fi
