#!/bin/bash

#~ remove_10g_ifs(){
    #~ nmcli con delete {nas,drbd}
    #~ rm -rf /etc/sysconfig/network-scripts/ifcfg-{nas,drbd}
#~ }

net_nas='172.31.0'
net_drbd='172.31.1'
net_pacemaker='172.31.2'
net_stonith='172.31.3'

update_ifs(){
    for new_if in $(ifconfig | cut -d ' ' -f1| tr ':' '\n' | awk NF)
    do
        if [[ $new_if == "nas" ]] || [[ $new_if == "drbd" ]] ; then
            set_if
        fi
    done
}

set_if(){
    if [[ $new_if == "nas" ]] || [[ $new_if == "drbd" ]]; then
        if [[ $new_if == "nas" ]]; then
            nmcli con mod "$new_if" ipv4.addresses $net_nas.$(($host+10))/24
        fi
        if [[ $new_if == "drbd" ]]; then
            nmcli con mod "$new_if" ipv4.addresses $net_drbd.$(($host+10))/24
            nmcli con mod "$new_if" ipv4.addresses $net_pacemaker.$(($host+10))/24
            nmcli con mod "$new_if" ipv4.addresses $net_stonith.$(($host+10))/24
        fi
        #~ nmcli con mod "$new_if" 802-3-ethernet.mtu 9000
    fi  
    
    nmcli dev disconnect "$new_if"
    nmcli con up "$new_if"

    MAC=$(cat /sys/class/net/$new_if/address)
    echo -n 'HWADDR="'$MAC\" >> /etc/sysconfig/network-scripts/ifcfg-$new_if
           
    #~ ip link set $new_if down
    #~ ip link set $new_if mtu 9000
    #~ ip link set $new_if up
}

set_viewers_if(){
    viewer_ip=$(ip -4 addr show viewers | grep -oP  "(?<=inet )[\d\.]+(?=/)" | head -1)
    viewer_mask=$(nmcli -t con show viewers  | grep IP4.ADDRESS | cut -d '/' -f 2)
    viewer_gw=$(nmcli -t con show viewers | grep IP4.GATEWAY | cut -d ':' -f 2)
    viewer_dns=$(nmcli -t con show viewers  | grep IP4.DNS | cut -d ':' -f 2 | tr "\n" " ")
    nmcli con mod viewers ipv4.method manual ipv4.addresses "${viewer_ip%.*}.$(($host+10))/$viewer_mask" ipv4.gateway "$viewer_gw" ipv4.dns "$viewer_dns"
    echo "VIEWER ADDRESS: ${viewer_ip%.*}.$(($host+10))/$viewer_mask GATEWAY: $viewer_gw DNS: $viewer_dns" > /root/isard-nets-viewer.cfg
    
    nmcli dev disconnect viewers
    nmcli con up viewers

    MAC=$(cat /sys/class/net/viewers/address)
    echo -n 'HWADDR="'$MAC\" >> /etc/sysconfig/network-scripts/ifcfg-viewers
}

host=$1
echo "if$host" > /etc/hostname
sysctl -w kernel.hostname=if$host
#remove_10g_ifs
update_ifs
set_viewers_if
