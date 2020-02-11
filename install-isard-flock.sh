#!/bin/bash

# Install on CentOS minimal server

#~ 1. MASTER (RAID+DRBD+PACEMAKER+NAS+DOCKER)
#~ 2. REPLICA (DRBD+PACEMAKER+NAS+DOCKER)
#~ 3. DISKLESS (PACEMAKER+NFS)

# USAGE (if needed parameter missing it will start TUI
# ./install-isard-flock.sh  \
#        --master 1 \
#        --if_viewers eth0,eth1 \
#        --if_nas eth2 \
#        --if_drbd eth3 \
#        --raid_level 1 \
#        --raid_devices /dev/vdb,/dev/vdc \
#        --pv_device /dev/md0 \
#        --isard_volume_size 210G \
#        --espurna_apikey 0123456789ABCDEF

touch /.installing

# Defaults (If set will bypass tui selection menu)
if_viewers=()       # (eth0 eth1 eth2)  If more than one set it will
                    # create a bonding between them.
if_nas=''           #'eth3'
if_drbd=''          #'eth4'

raid_level=-1       #1
raid_devices=()     # (/dev/vdb /dev/vdc)
pv_device=''        # "/dev/md0"
isard_volume_size='' # Volume size of isard storage (for everything).
                         # Should fit in your cluster storage, so select
                         # the maximum size of the smallest storage size
                         # in the cluster drbd minus 1GB (I need it!)
                         # Examples: 470M, 200G, 2000G
master_node=-1      # 1 yes, 0 no

espurna_fencing=0   # 0 no, 1 yes
espurna_apikey=""   # Set up the espurna_apikey from your IoT plug device.


### DO NOT MODIFY FROM HERE

net_nas='172.31.0'
net_drbd='172.31.1'
net_pacemaker='172.31.2'
net_stonith='172.31.3'

### Command line args
while true; do
  case "$1" in
    --if_viewers )  IFS=',' read -r -a if_viewers  <<< "$2"; shift 2;;
    --if_nas )      if_nas=$2; shift 2;;
    --if_drbd )     if_drbd=$2; shift 2;;
    
    --raid_level )  raid_level=$2; shift 2;;
    --raid_devices ) IFS=',' read -r -a raid_devices  <<< "$2"; shift 2;;
    --pv_device )   pv_device=$2; shift 2;;
    
    --isard_volume_size ) isard_volume_size=$2; shift 2;;
    --master )      master_node=$2; shift 2;;
    --espurna_apikey )  espurna_apikey=$2; espurna_fencing=1; shift 2;;
    -- ) shift; break ;;
    * ) break ;;
  esac
done
### End command line args

## FUNCTIONS
install_base_pkg(){
    systemctl disable --now firewalld
    sed -i s/^SELINUX=.*$/SELINUX=disabled/ /etc/selinux/config && setenforce 0
    setenforce 0
    rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
    yum install -y https://www.elrepo.org/elrepo-release-7.0-3.el7.elrepo.noarch.rpm
    yum install -y nano git sshpass rsync nc dialog
    systemctl enable --now chronyd
    cp ./resources/scripts/update_interfaces.sh /usr/local/bin/
}

remove_all_if(){
    nmcli --fields UUID,TIMESTAMP-REAL con show |  awk '{print $1}' | while read line; do nmcli con delete uuid  $line;    done
    rm -rf /etc/sysconfig/network-scripts/ifcfg-{nas,drbd,viewers}
}

get_ifs(){
    i=1
    unset var
    unset interfaces
    message="\n"
    system_ifs=(lo viewers nas drbd)
    for iface in $(ifconfig | cut -d ' ' -f1| tr ':' '\n' | awk NF)
    do
        if [[ $iface == "" ]] || [[ $iface == "docker0" ]] || [[ ${system_ifs[*]} =~ "$iface" ]] ; then continue; fi
        interfaces+=("$iface")
        var="$var $i $iface "
        speed=$(cat /sys/class/net/$iface/speed)
        if [[ $? -ne 0 ]]; then
            speed="?"
        fi
        if [[ $speed == "-1" ]]; then
            speed="?"
        fi
        mac=$(cat /sys/class/net/$iface/address)
        if_ip=$(ip addr show $iface | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
        message="$message\n$i - $iface - $mac - $if_ip - speed = $speed"
        i=$((i+1))
    done
    var="$var $((${#interfaces[@]}+1)) skip"
}

set_if(){
    # original final
    # Now only handles nas and drbd. Maybe it can be changed as there
    # is only a viewers bond with all the interfaces for viewers handled
    # in its own function
    if [[ $new_if == "nas" ]] || [[ $new_if == "drbd" ]]; then
        if [[ $host == 1 ]]; then
            fhost=11
        else
            fhost=254
        fi
        if [[ $new_if == "nas" ]]; then
            nmcli con add con-name "$new_if" ifname $old_if type ethernet ip4 $net_nas.$fhost/24
        fi
        if [[ $new_if == "drbd" ]]; then
            nmcli con add con-name "$new_if" ifname $old_if type ethernet ip4 $net_drbd.$fhost/24
            nmcli connection modify "$new_if" +ipv4.addresses $net_pacemaker.$fhost/24
            nmcli connection modify "$new_if" +ipv4.addresses $net_stonith.$fhost/24
        fi
        nmcli con mod "$new_if" 802-3-ethernet.mtu 9000
    else
        nmcli con add con-name "$new_if" ifname $old_if type ethernet ipv4.method auto
    fi
    nmcli con mod "$new_if" connection.interface-name "$new_if"
    nmcli con mod "$new_if" ipv6.method ignore
    MAC=$(cat /sys/class/net/$old_if/address)
    echo -n 'HWADDR="'$MAC\" >> /etc/sysconfig/network-scripts/ifcfg-$new_if
    ip link set $old_if down
    ip link set $old_if name $new_if
    if [[ $new_if == "nas" ]] || [[ $new_if == "drbd" ]]; then
        ip link set $new_if mtu 9000
    fi
    ip link set $new_if up
    nmcli con up "$new_if"
    get_ifs
}

set_viewers_bonding(){
    nmcli con add type bond ifname viewers con-name viewers ipv4.method auto bond.options mode=802.3ad,miimon=100,lacp_rate=fast,xmit_hash_policy=1
    #~ "mode=802.3ad miimon=100 updelay=12000 downdelay=0 xmit_hash_policy=1"
    #~ mode=802.3ad,miimon=100,lacp_rate=fast,xmit_hash_policy=layer2+3
    for if in ${if_viewers[@]}
    do
        nmcli con add type ethernet ifname "$if" master viewers
        ip link set $if up
        nmcli con up "$if"
    done    
    ip link set viewers up
    nmcli con up viewers
}

set_viewers_if(){
    var=""
    i=1
    for dev in ${interfaces[@]}
    do
        var="$var $i $dev off "
        i=$((i+1))
    done
    if [[ ${#if_viewers[@]} -eq 0 ]]; then 
        cmd=(dialog --separate-output --checklist "Select 1 or more (bonding) Isard network interface[s]:$message" 22 76 16)
        options=($var)
        choices=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty) 
        for c in $choices
        do
            if_viewers+=(${interfaces[$(($c-1))]})
        done
    fi

    
    if [[ ${#if_viewers[@]} -eq 1 ]]; then 
        old_if=${if_viewers[0]}
        new_if="viewers"
        set_if
    fi
    if [[ ${#if_viewers[@]} -gt 1 ]]; then 
        set_viewers_bonding
    fi
    


}

set_master_viewer_ip(){
    viewer_ip=$(ip addr show viewers | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
    nmcli connection modify viewers +ipv4.addresses "${viewer_ip%.*}.11/32"
    nmcli dev disconnect viewers
    nmcli con up viewers
}

set_nas_if(){
    if [[ $if_nas == 'none' ]]; then
        return
    fi
    if [[ $if_nas == '' ]] ; then
    opt=$(dialog --menu --stdout "Select interface for NAS:$message" 22 76 16 $var )
        if ! [[ $opt -gt ${#interfaces[@]} ]]; then
            old_if=${interfaces[$(($opt-1))]}
            new_if="nas"
            set_if
        fi
    else
        old_if=$if_nas
        new_if="nas"
        set_if
    fi      
}

set_drbd_if(){
    if [[ $if_drbd == 'none' ]]; then
        return
    fi
    if [[ $if_drbd == '' ]] ; then
        opt=$(dialog --menu --stdout "Select interface for DRBD:$message" 22 76 16 $var )
        if ! [[ $opt -gt ${#interfaces[@]} ]]; then
            old_if=${interfaces[$(($opt-1))]}
            new_if="drbd"
            set_if
        fi
    else
        old_if=$if_drbd
        new_if="drbd"
        set_if
    fi
}

#~ set_internet_if(){
    #~ if [[ $if_internet == 'none' ]]; then
        #~ return
    #~ fi
    #~ if [[ $if_internet == '' ]] ; then
        #~ opt=$(dialog --menu --stdout "Select interface for guests INTERNET:" 0 0 0 $var )
        #~ if ! [[ $opt -gt ${#interfaces[@]} ]]; then
            #~ old_if=${interfaces[$(($opt-1))]}
            #~ new_if="internet"
            #~ set_if
        #~ fi
    #~ else
        #~ old_if=$if_internet
        #~ new_if="internet"
        #~ set_if
    #~ fi
#~ }

create_raid(){
    rpm -qa | grep mdadm
    if [[ $? == 1 ]] ; then
        yum install -y mdadm
    fi
    for d in "${raid_devices[@]}" 
    do
        dd if=/dev/zero of=$d bs=2048 count=4096
    done
    yes | mdadm --create --verbose $pv_device --level=$raid_level --raid-devices=${#raid_devices[@]} ${raid_devices[@]}
    #~ sudo mdadm --detail --scan > /etc/mdadm.conf
    echo "ARRAY $pv_device metadata=1.2" > /etc/mdadm.conf
}

create_drbdpool(){
    rpm -qa | grep lvm2
    if [[ $? == 1 ]] ; then
        yum install -y lvm2
    fi
    rpm -qa | grep kmod-drbd90
    if [[ $? == 1 ]] ; then
        yum install -y kmod-drbd90 drbd90-utils java-1.8.0-openjdk
    fi
    #~ echo 'global_filter= [ "a|/dev/md0|", "r|.*/|" ]' >> /etc/lvm/lvm.conf
    echo "Creating drbdpool on $pv_device ..."
    pvcreate $pv_device
    vgcreate drbdpool $pv_device
    echo "drbdppool created..."
    rpm -ivh ./resources/linstor/python-linstor*.rpm \
        ./resources/linstor/linstor-common-*.rpm  \
        ./resources/linstor/linstor-controller-*.rpm  \
        ./resources/linstor/linstor-satellite-*.rpm \
        ./resources/linstor/linstor-client-*rpm
    cp ./resources/linstor/linstor-satellite.service /usr/lib/systemd/system
    cp ./resources/linstor/linstor-controller.service /usr/lib/systemd/system
    cp ./resources/linstor/linstor-client.conf /etc/linstor/
    #~ systemctl enable --now linstor-satellite (it is done when setting it up)
}

set_isard_volume_size(){
    if [[ ! -z $isard_volume_size ]]; then
        ### It is already set
        return
    fi
    size=$(pvs --units g --separator ";" $pv_device | grep $pv_device | cut -d ";" -f5 | cut -d "," -f 1)
    size=$(($size-1)) # We need some MB for linstor database storage
    if [ $size -lt 2 ]; then # We are in test environment, set a minimum size
        isard_volume_size='470M'
        return
    fi
    units='G' 
    dialog --title "Isard volume storage" \
    --backtitle "Do you want to use maximum storage available:?" \
    --yesno "The maximum size for Isard volume is $size GIGABYTES.\n Use full size?" 7 60
    if [[ $? == 0 ]] ; then
        isard_volume_size='$size$units'
    else
        size=$(dialog --stdout --inputbox "Enter maximum size IN GIGABYTES for Isard volume <=$size G:" 8 40)
        size=$(echo $size | cut -d "G" -f 1 | cut -d "g" -f 1)
        isard_volume_size='$size$units'
    fi  
}

set_storage_dialog(){
    storage_message="\n$(fdisk -l | grep Disk | grep /dev/[nvs])"
    var=""
    i=1
    for dev in ${devs[@]}
    do
        if [[ $var == "" ]]; then
            var="$var $i $dev off "
        else
            var="$var $i $dev on "
        fi
        i=$((i+1))
    done

    if [[ ${#devs[@]} -eq 2 ]]; then
        # NO RAID
        var=""
        i=1
        for dev in ${devs[@]}
        do
            var="$var $i $dev "
            i=$((i+1))
        done
        opt=$(dialog --menu --stdout "Select storage device:$storage_message" 22 76 16 $var )
        pv_device="/dev/${devs[$(($opt-1))]}"
        create_drbdpool
        set_isard_volume_size
    fi
    if [[ ${#devs[@]} -eq 3 ]]; then
        # RAID 1 - 2 DISKS
        cmd=(dialog --separate-output --checklist "Select 2 devices for RAID 1:$storage_message" 22 76 16)
        options=($var)
        choices=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)       
        for c in $choices
        do
            raid_sdevs="$raid_sdevs /dev/${devs[$(($c-1))]}"
        done
        raid_devices=(${raid_sdevs[@]})
        raid_level=1
        create_raid
        pv_device="/dev/md0"
        create_drbdpool
        set_isard_volume_size
    fi
    if [[ ${#devs[@]} -eq 4 ]]; then
        # RAID 1 - 2 DISKS + SPARE
        # RAID 5 - 3 DISKS
        echo "Not implemented"
    fi
    if [[ ${#devs[@]} -gt 4 ]]; then
        # RAID 5 - 3 DISKS + SPARE
        # RAID 10 - 4 DISKS
        echo "Not implemented"
    fi

}

set_storage(){
    if [[ $raid_level == -1 ]] ; then
        set_storage_dialog  
    else
        create_raid
        create_drbdpool
    fi  
}

set_pacemaker(){
    yum install -y corosync pacemaker pcs python-pycurl python-requests fence-agents-common
    #fence-agents-apc fence-agents-apc-snmp
    cp ./resources/pcs/fence_espurna /usr/sbin/
    chmod 755 /usr/sbin/fence_espurna
    cp ./resources/pcs/compose /usr/lib/ocf/resource.d/heartbeat/
    systemctl enable pcsd
    systemctl enable corosync
    systemctl enable pacemaker
    usermod --password $(echo isard-flock | openssl passwd -1 -stdin) hacluster
    systemctl start pcsd
}

set_docker(){
  if ! yum list installed docker-ce >/dev/null 2>&1 || [[ ! -f /usr/local/bin/docker-compose ]]; then
    sudo yum remove docker \
                      docker-client \
                      docker-client-latest \
                      docker-common \
                      docker-latest \
                      docker-latest-logrotate \
                      docker-logrotate \
                      docker-engine
    sudo yum install -y yum-utils \
      device-mapper-persistent-data \
      lvm2
    sudo yum-config-manager \
        --add-repo \
        https://download.docker.com/linux/centos/docker-ce.repo
    sudo yum install -y docker-ce docker-ce-cli containerd.io
    sudo curl -L "https://github.com/docker/compose/releases/download/1.24.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
  else
    echo "docker & docker-compose already installed"
  fi
  sudo systemctl enable docker --now
  echo "Pulling Isard $TAG docker images"
    if [[ $espurna_fencing == 1 ]]; then
        docker-compose -f /opt/isard-flock/resources/compose/docker-compose.yml pull
    else
        docker-compose -f /opt/isard-flock/resources/compose/docker-compose-without-mosquitto.yml pull
    fi  
  
}


#### MASTER FUNCTIONS ####
set_master_node(){
    # Hostname & keys & ntp & basic packages
    echo "if$host" > /etc/hostname
    sysctl -w kernel.hostname=if$host

    if [[ ! -f ~/.ssh/id_dsa  ]]; then
        ssh-keygen -t dsa -f ~/.ssh/id_dsa -N ""
        cp ~/.ssh/id_dsa.pub ~/.ssh/authorized_keys
    fi
    
    ### DRBD
    # Enable services
    systemctl enable --now linstor-controller
    sleep 5
    #~ cp ../_data/linstor-client.conf /etc/linstor/
    systemctl enable --now linstor-satellite
    sleep 5
    
    # Create node & resources
    linstor node create if$host $net_drbd.1$host
    linstor storage-pool create lvm if$host data drbdpool
    linstor resource-definition create isard
    linstor volume-definition create isard $isard_volume_size
    linstor resource create isard --auto-place 1 --storage-pool data
    sleep 5

    # Create filesystem
    mkfs.ext4 /dev/drbd/by-res/isard/0

    ## LINSTORDB STORAGE
    # Linstor saves it's data in /var/lib/linstor. In order to have this
    # data HA we should create a new resource that will be held by pcs
    # as a Master/Slave, not as a drbd9 one.
    linstor resource-definition create linstordb
    linstor volume-definition create linstordb 250M
    linstor resource create linstordb --auto-place 1 --storage-pool data
    systemctl disable --now linstor-controller
    rsync -avp /var/lib/linstor /tmp/
    mkfs.ext4 /dev/drbd/by-res/linstordb/0
    rm -rf /var/lib/linstor/*
    mount /dev/drbd/by-res/linstordb/0 /var/lib/linstor
    rsync -avp /tmp/linstor/ /var/lib/linstor/
    
    ### PACEMAKER
    # Add host & start cluster
    #~ usermod --password $(echo isard-flock | openssl passwd -1 -stdin) hacluster
    pcs cluster auth if$host-pacemaker <<EOF
hacluster
isard-flock
EOF
    pcs cluster setup --name isard if$host-pacemaker
    pcs cluster enable
    pcs cluster start if$host-pacemaker

    pcs resource defaults resource-stickiness=100
    
    # Stonith 
    if [[ $espurna_fencing == 1 ]]; then
        pcs stonith create stonith fence_espurna ipaddr=$net_stonith.100 apikey=$espurna_apikey pcmk_host_list="if1-pacemaker,if2-pacemaker,if3-pacemaker,if4-pacemaker,if5-pacemaker,if6-pacemaker,if7-pacemaker,if8-pacemaker" pcmk_host_map="if1-pacemaker:1;if2-pacemaker:2;if3-pacemaker:3;if4-pacemaker:4;if5-pacemaker:5;if6-pacemaker:6;if7-pacemaker:7;if8-pacemaker:8" pcmk_host_check=static-list power_wait=5 passwd=acme
    else
        pcs property set stonith-enabled=false
    fi
    
    # Linstordb Master/Slave & linstor controller
    pcs resource create linstordb-drbd ocf:linbit:drbd drbd_resource=linstordb op monitor interval=15s role=Master op monitor interval=30s role=Slave
    pcs resource master linstordb-drbd-clone linstordb-drbd master-max=1 master-node-max=1 clone-max=8 clone-node-max=1 notify=true
    pcs resource create linstordb-fs Filesystem \
            device="/dev/drbd/by-res/linstordb/0" directory="/var/lib/linstor" \
            fstype="ext4" "options=defaults,noatime,nodiratime,noquota" op monitor interval=10s
    pcs resource create linstor-controller systemd:linstor-controller

    pcs resource group add linstor linstordb-fs linstor-controller
    pcs constraint order promote linstordb-drbd-clone then linstor INFINITY \
        require-all=true symmetrical=true \
        setoptions kind=Mandatory
    pcs constraint colocation add \
        linstor with master linstordb-drbd-clone INFINITY 

    # Cluster needed policy
    pcs property set no-quorum-policy=ignore

    # Isard storage & nfs exports
    mkdir /opt/isard
    pcs resource create isard_fs Filesystem device="/dev/drbd/by-res/isard/0" directory="/opt/isard" fstype="ext4" "options=defaults,noatime,nodiratime,noquota" op monitor interval=10s

    yum install nfs-utils -y
    pcs resource create nfs-daemon systemd:nfs-server 
    pcs resource create nfs-root exportfs \
    clientspec=$net_nas.0/255.255.255.0 \
    options=rw,crossmnt,async,wdelay,no_root_squash,no_subtree_check,sec=sys,rw,secure,no_root_squash,no_all_squash \
    directory=/opt/ \
    fsid=0

    pcs resource create isard_data exportfs \
    clientspec=$net_nas.0/255.255.255.0 \
    wait_for_leasetime_on_stop=true \
    options=rw,mountpoint,async,wdelay,no_root_squash,no_subtree_check,sec=sys,rw,secure,no_root_squash,no_all_squash directory=/opt/isard \
    fsid=11 \
    op monitor interval=30s

    # Isard floating IP
    pcs resource create isard-ip ocf:heartbeat:IPaddr2 ip=$net_nas.1 cidr_netmask=32 nic=nas:0  op monitor interval=30 

    #~ viewer_ip=$(ip addr show viewers | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
    #~ pcs resource create viewers-ip ocf:heartbeat:IPaddr2 ip=$viewer_ip cidr_netmask=32 nic=viewers:0  op monitor interval=30
    
    # Isard compose
    if [[ $espurna_fencing == 1 ]]; then
        compose='docker-compose.yml'
    else
        compose='docker-compose-without-mosquitto.yml'
    fi 
    pcs resource create isard-compose ocf:heartbeat:compose \
            conf="/opt/isard-flock/resources/compose/$compose" \
            env_path="/opt/isard-flock/resources/compose" \
            force_kill="true" \
            op start interval=0s timeout=300s \
            op stop interval=0 timeout=300s \
            op monitor interval=60s timeout=60s
    # Group and constraints
    #~ pcs resource group add server linstordb-fs linstor-controller isard_fs nfs-daemon nfs-root isard_data isard-ip
    #~ pcs constraint order set linstordb-fs linstor-controller isard_fs nfs-daemon nfs-root isard_data isard-ip

    pcs resource group add server isard_fs nfs-daemon nfs-root isard_data isard-ip isard-compose
    pcs constraint order set linstor server
    
    ## NFS client nodes configuration (should avoid isard nfs server colocation)
    pcs resource create nfs-client Filesystem \
            device=isard-nas:/isard directory="/opt/isard" \
            fstype="nfs" "options=defaults,noatime" op monitor interval=10s
    pcs resource clone nfs-client clone-max=8 clone-node-max=8 notify=true
    #~ pcs constraint colocation add nfs-client-clone with isard-ip -INFINITY
    pcs constraint colocation add nfs-client-clone with server -INFINITY

    ## Isard hypervisor docker (should avoid isard server colocation)
    pcs resource create hypervisor ocf:heartbeat:compose \
            conf="/opt/isard-flock/resources/compose/hypervisor.yml" \
            env_path="/opt/isard-flock/resources/compose" \
            force_kill="true" \
            op start interval=0s timeout=300s \
            op stop interval=0 timeout=300s \
            op monitor interval=60s timeout=60s 
    pcs resource clone hypervisor clone-max=8 clone-node-max=8 notify=true
    pcs constraint colocation add hypervisor-clone with server -INFINITY
    
    ## Just to be sure it prefers the first one. Avoidable...
    pcs constraint location server prefers if1=200
    
    ### TODO: Resource stickiness (cluster wide?)
        
    ### This cron will monitor for new nodes (isard-new) and lauch auto config
    cp ./resources/scripts/update_interfaces.sh /usr/local/bin/
    cp ./resources/config/cron-isard-new.sh /usr/local/bin/
    chmod a+x /usr/local/bin/cron-isard-new.sh
    cp ./resources/config/cron-isard-new /etc/cron.d/   

}

set_optimizations(){
    return
    # drbd
    # linstor resource-definition drbd-options --al-extents 6007 isard
    
    # 10g irq affinity
    
    # tcp/ip stack sysctl for 10G
}
##########################


show_final_config(){
    echo "#### INTERFACES ####" >> /root/isard.cfg
    echo "viewers ip: $(ip addr show viewers | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)" >> /root/isard.cfg
    echo "    nas ip: $(ip addr show nas | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)" >> /root/isard.cfg
    echo "   drbd ip: $(ip addr show drbd | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)" >> /root/isard.cfg
    cat /root/isard.cfg
}

mkdir /var/log/isard-flock
echo "#### SETTING /etc/hosts for isard-flock cluster ####\n#########################"
scp ./resources/config/hosts /etc/hosts
echo "#### INSTALL base packages needed ####\n#########################"
install_base_pkg

if [[ $master_node == -1 ]]; then
    dialog --title "Master node" \
    --backtitle "Is this the first (master) node?" \
    --yesno "Set up as MASTER node?" 7 60
    if [[ $? == 0 ]] ; then
        master_node=1
        dialog --title "Fencing with espurna IoT" \
        --backtitle "Are you using espurna flashed IoT fencing device? RECOMMENDED" \
        --yesno "Set up espurna IoT fencing apikey?" 7 60
        if [[ $? == 0 ]] ; then
            res=$(dialog --stdout --inputbox "Enter your espurna device apikey:" 8 40)
            if [[ ! -z $res ]] ; then
                espurna_fencing=1
                espurna_apikey=$res
            fi
        fi
    else
        master_node=0
    fi
fi

if [[ $master_node == 0 ]]; then
    host=254 # Isard_new
fi
if [[ $master_node == 1 ]]; then
    host=1
fi

echo "#### REMOVE all interface configurations ####\n#########################"
remove_all_if
get_ifs

# STORAGE
devs=($(lsblk -d -n -oNAME,RO | grep '0$' | awk '!/sr0/' | awk {'print $1'}))
if [[ ${#devs[@]} -gt 2 ]]; then
    # secondary master
    echo "#### CONFIGURE drbd interface (172.31.0.X) ####\n#########################"
    set_drbd_if
    echo "#### CONFIGURE nas interface (172.30.0.X) ####\n#########################"
    set_nas_if
    echo "#### CONFIGURE isard interface with dhcp ####\n#########################"
    set_viewers_if
    #~ set_internet_if

    echo "#### CONFIGURE storage ####\n#########################"
    set_storage
    echo "#### CONFIGURE pacemaker cluster ####\n#########################"
    set_pacemaker
    echo "#### INSTALL docker & docker-compose ####\n#########################"
    set_docker
    if [[ $master_node == 1 ]]; then
        set_master_viewer_ip
        set_master_node
        #~ install_master_isard
    fi
fi
if [[ ${#devs[@]} -eq 2 ]]; then
    # replica
    set_drbd_if
    set_nas_if
    set_viewers_if
    #~ set_internet_if
    
    set_storage
    set_pacemaker
    set_docker
    if [[ $master_node == 1 ]]; then
        set_master_viewer_ip
        set_master_node
    fi
fi
if [[ ${#devs[@]} -eq 1 ]]; then
    # diskless
    set_nas_if
    set_viewers_if
    #~ set_internet_if

    set_pacemaker
fi

rm /.installing
show_final_config
#~ if [[ $0 == "auto-install.sh" ]]; then
    #~ rm $0
#~ fi
