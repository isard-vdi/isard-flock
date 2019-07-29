#!/bin/bash

remove_10g_ifs(){
	nmcli con delete {nas,drbd}
	rm -rf /etc/sysconfig/network-scripts/ifcfg-{nas,drbd}
}

update_ifs(){
	for new_if in $(ifconfig | cut -d ' ' -f1| tr ':' '\n' | awk NF)
	do
		if [[ $new_if == "nas" ]] || [[ $new_if == "drbd" ]] ; then
			set_if
		fi
	done
}

set_if(){
	net=0
	if [[ $new_if == "drbd" ]]; then net=1; fi
	nmcli con mod "$new_if" ipv4.addresses 172.31.$net.$(($host+10))/24
	nmcli dev disconnect "$new_if"
	nmcli con up "$new_if"
	#~ ip link set $new_if down
	#~ ip link set $new_if mtu 9000
	#~ ip link set $new_if up
}

host=$1
echo "if$host" > /etc/hostname
sysctl -w kernel.hostname=if$host
#~ remove_10g_ifs
update_ifs
