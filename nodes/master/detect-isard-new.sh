if ping -c 1 isard-new &> /dev/null
then
  echo "Found new isard. Get new host number..."
  host=1
  while nc -z "if$host" 22 2>/dev/null; do
    host=$((host+1))
  done

  /usr/bin/rsync -ratlz --rsh="/usr/bin/sshpass -p isard-flock ssh -o StrictHostKeyChecking=no -l root" /root/.ssh/*  isard-new:/root/.ssh/
  scp -r /root/isard-flock isard-new:/root/
  ssh -n -f isard-new "bash -c 'nohup /root/isard-flock/nodes/master/other-masters.sh > /dev/null 2>&1 &'"
  # ssh	isard-new -- bash other-masters.sh &
  sleep 10
  # while ...
  pcs cluster auth if$host <<EOF
hacluster
isard-flock
EOF
  pcs cluster node add if2
  pcs cluster start if2
else
  echo "Not found"
fi
