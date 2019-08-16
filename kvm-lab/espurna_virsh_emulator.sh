#!/bin/bash
nmcli con show nas > /dev/null
if [[ $? -eq 10 ]]; then
	nmcli --fields UUID,TIMESTAMP-REAL con show |  awk '{print $1}' | while read line; do nmcli con delete uuid  $line;    done
	rm -rf /etc/sysconfig/network-scripts/ifcfg-{eth0,eth1}
	nmcli con add con-name eth0 ifname eth0 type ethernet ipv4.method auto
	nmcli con add con-name nas type ethernet ifname eth1 ip4 172.31.0.101/24 ip4 172.31.0.102/24 ip4 172.31.0.103/24 ip4 172.31.0.104/24 ip4 172.31.0.105/24 ip4 172.31.0.106/24 ip4 172.31.0.107/24 ip4 172.31.0.108/24
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
