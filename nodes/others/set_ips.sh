#!/bin/bash

# exit when any command fails
set -e

# keep track of the last executed command
trap 'last_command=$current_command; current_command=$BASH_COMMAND' DEBUG
# echo an error message before exiting
trap 'echo "\"${last_command}\" command filed with exit code $?."' EXIT

remove_10g_ifs(){
	nmcli con delete {nas,drbd}
	rm -rf /etc/sysconfig/network-scripts/ifcfg-{nas,drbd}
}

update_ifs(){
	for new_if in $(ifconfig | cut -d ' ' -f1| tr ':' '\n' | awk NF)
	do
		if [[ $new_if == "drbd" ]] || [[ $new_if == "drbd" ]] ; then
			set_if
		fi
	done
}

set_if(){
	net=0
	if [[ $new_if == "drbd" ]]; then net=1; fi
	nmcli con add con-name "$new_if" ifname $old_if type ethernet ip4 172.31.$net.$(($host+10))/24
	nmcli con mod "$new_if" ipv6.method ignore
	nmcli con mod "$new_if" 802-3-ethernet.mtu 9000
	MAC=$(cat /sys/class/net/$new_if/address)
	echo -n 'HWADDR="'$MAC\" >> /etc/sysconfig/network-scripts/ifcfg-$new_if
	ip link set $new_if down
	ip link set $new_if mtu 9000
	ip link set $new_if up
}

remove_10g_ifs
update_ifs
