if ping -c 1 isard-new &> /dev/null
then
  echo "Found new isard"
  /usr/bin/rsync -ratlz --rsh="/usr/bin/sshpass -p isard-flock ssh -o StrictHostKeyChecking=no -l root" /root/.ssh/*  isard-new:/root/.ssh/
  scp other-masters.sh isard-new:
  # ssh -n -f isard-new "bash -c 'nohup other-masters.sh > /dev/null 2>&1 &'"
  # ssh	isard-new -- bash other-masters.sh &
  # while ...
  pcs cluster auth if$host <<EOF
hacluster
isard-flock
EOF
else
  echo "Not found"
fi
