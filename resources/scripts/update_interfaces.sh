#!/bin/bash

#~ remove_10g_ifs(){
    #~ nmcli con delete {nas,drbd}
    #~ rm -rf /etc/sysconfig/network-scripts/ifcfg-{nas,drbd}
#~ }

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

    MAC=$(cat /sys/class/net/$new_if/address)
    echo -n 'HWADDR="'$MAC\" >> /etc/sysconfig/network-scripts/ifcfg-$new_if
        
    #~ ip link set $new_if down
    #~ ip link set $new_if mtu 9000
    #~ ip link set $new_if up
}

set_viewers_if(){
    viewer_ip=$(ip addr show viewers | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
    nmcli connection modify viewers +ipv4.addresses "${viewer_ip%.*}.$(($host+10))/32"
    nmcli dev disconnect viewers
    nmcli con up viewers
}

host=$1
echo "if$host" > /etc/hostname
sysctl -w kernel.hostname=if$host
#remove_10g_ifs
update_ifs
set_viewers_if
