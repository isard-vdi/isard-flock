#!/bin/bash

remove_10g_ifs(){
	nmcli --fields UUID,TIMESTAMP-REAL con show |  awk '{print $1}' | while read line; do nmcli con delete uuid  $line;    done
	rm -rf /etc/sysconfig/network-scripts/ifcfg-{nas,drbd,viewers,internet}
}

set_if(){
	# original final
	if [[ $new_if == "nas" ]] || [[ $new_if == "drbd" ]]; then
		net=0
		if [[ $new_if == "drbd" ]]; then net=1; fi
		nmcli con add con-name "$new_if" ifname $old_if type ethernet ip4 172.31.$net.254/24
	else
		nmcli con add con-name "$new_if" ifname $old_if type ethernet ipv4.method auto
	fi
	nmcli con mod "$new_if" connection.interface-name "$new_if"
	nmcli con mod "$new_if" ipv6.method ignore
	if [[ $new_if == "nas" ]] || [[ $new_if == "drbd" ]]; then
		nmcli con mod "$new_if" 802-3-ethernet.mtu 9000
	fi
	MAC=$(cat /sys/class/net/$old_if/address)
	echo -n 'HWADDR="'$MAC\" >> /etc/sysconfig/network-scripts/ifcfg-$new_if
	ip link set $old_if down
	ip link set $old_if name $new_if
	if [[ $new_if == "nas" ]] || [[ $new_if == "drbd" ]]; then
		ip link set $new_if mtu 9000
	fi
	ip link set $new_if up
    nmcli con up "$new_if"
}

echo "isard-new" > /etc/hostname
sysctl -w kernel.hostname="isard-new"
remove_10g_ifs

ip link set {viewers,nas,drbd} down
ip link set drbd name eth1
ip link set nas name eth2
ip link set viewers name eth0
ip link set {viewers,nas,drbd} up

new_if=viewers
old_if=eth0
set_if

new_if=drbd
old_if=eth1
set_if

new_if=nas
old_if=eth2
set_if
