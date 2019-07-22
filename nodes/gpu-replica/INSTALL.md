# ISARD-FLOCK - GPU REPLICA



## Intel GVT

```bash
git clone repo: https://github.com/intel/gvt-linux
cd gvt-linux && cp -v /boot/config-$(uname -r) .config
make menuconfig
make -j 4
make modules_install
make install
    edit /etc/default/grub -> GRUB_CMDLINE_LINUX="i915.enable_gvt=1 kvm.ignore_msrs=1 intel_iommu=on i915.enable_guc=0 rhgb quiet"
grub2-mkconfig -o /boot/grub2/grub.cfg
echo "kvmgt vfio-iommu-type1 vfio-mdev" > /etc/modules-load.d/gvt.conf
reboot
    check mdev existence
ls /sys/devices/pci0000:00/0000:00:02.0/mdev_supported_types/
i915-GVTg_V5_4  i915-GVTg_V5_8

```

