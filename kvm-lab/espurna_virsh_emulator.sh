#!/bin/bash
#~ cp /opt/* /root/.ssh/
nmcli con show drbd > /dev/null
if [[ $? -eq 10 ]]; then
	nmcli --fields UUID,TIMESTAMP-REAL con show |  awk '{print $1}' | while read line; do nmcli con delete uuid  $line;    done
	rm -rf /etc/sysconfig/network-scripts/ifcfg-{eth0,eth1}
	nmcli con add con-name eth0 ifname eth0 type ethernet ipv4.method auto
	nmcli con add con-name nas type ethernet ifname eth1 ip4 172.31.3.101/24 ip4 172.31.3.102/24 ip4 172.31.3.103/24 ip4 172.31.3.104/24 ip4 172.31.3.105/24 ip4 172.31.3.106/24 ip4 172.31.3.107/24 ip4 172.31.3.108/24
fi
sleep 5
rpm -ql python-flask
if [[ $? -eq 1 ]]; then
	yum install -y python-flask
fi
rpm -ql libvirt-python
if [[ $? -eq 1 ]]; then
	yum install -y libvirt-python
fi
/bin/python /opt/isard-flock/kvm-lab/espurna_virsh_emulator.py
