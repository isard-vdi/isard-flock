# ISARD-FLOCK INSTALL


## MASTER NODE

It's the first one. Recommended install with isard-flock-iso.

### Requirements

- SYSTEM:
    - One SSD (sda). If not change accordingly ks.cfg before building iso:
        ignoredisk --only-use=sda
- STORAGE: Isard will create RAID 1 if two devices found.
    - MINIMUM: One SSD (sdb) or NVME (nvme0p1)
    - RECOMMENDED: Two SSD (sdb,sdc) or two NVME (nvme0p1,nvme1p1)
- NETWORK:
    - VIEWERS: Access to IsardVDI web and virtual desktops viewers and
        Internet connection.
        - MINIMUM: One gigabit interface. Must be set a fixed IP in your
            dhcp server before installing. Install will fix that IP as static.
        - RECOMMENDED: One 10G interface or multiple 1G interfaces.
            Install script will create bond between 1G interfaces if needed.
    - NAS: Access to storage when multiple nodes in cluster. You must
        use a switch with >=9000 MTU configuration.
    - DRBD: Access to storage replication when multiple nodes in cluster.
        You must use a switch with >=9000MTU configuration.
- STONITH: Not required but recommended. 
    - MINIMUM: Not installed. If node fails manual shutdown of node must
        be performed
    - RECOMMENDED: Use espurna flashed plug devices on each node power
        plug. Set up the same espurna api key on each plug and set up
        in isard-flock during install.
        NAS network will be used and each plug should be 172.31.0.10X
        where X is the node number. Use espurna flashed plug devices only.
        Read isard-mosquitto docker README for configuration.

Before installing from this script:

1. Set your access interface (viewers) in your dhcp with a fixed address
    - Installation with set this IP as static one
2. NAS interface will be set at 172.30.0.X/24 network
3. DRBD interface will be set at 172.31.0.X/24 network
4. Pacemaker cluster will use NAS interface for corosync
5. DRBD
