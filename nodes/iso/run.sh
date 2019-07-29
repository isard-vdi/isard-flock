rm -rf /mnt/bootisoks
umount /mnt/iso
mkdir /mnt/iso
mount -o loop /mnt/CentOS-7-x86_64-Minimal-1810.iso  /mnt/iso
mkdir /mnt/bootisoks
cp -r /mnt/iso/* /mnt/bootisoks/
umount /mnt/iso

#rm -rf /mnt/bootisoks/Packages/*
#cp /mnt/packages/* /mnt/bootisoks/Packages
#cp /mnt/linstor/* /mnt/bootisoks/Packages
#cd /mnt/bootisoks/Packages/
#yum install createrepo -y

#rm -rf /mnt/bootisoks/repodata
#rm -rf /mnt/bootisoks/repodata/*.gz /mnt/bootisoks/repodata/*.bz2
#createrepo /mnt/bootisoks/Packages -g /mnt/bootisoks/repodata -o /mnt/bootisoks/ -u file:///run/install/repo/Packages/
#createrepo --update --groupfile /mnt/comps.xml -u file:///run/install/repo/Packages/ -dpo .. .
#cp /mnt/comps.xml /mnt/bootisoks/repodata
#createrepo -g /mnt/comps.xml -u file:///run/install/repo/Packages/ -dpo .. .

cd /mnt
cp ks.cfg /mnt/bootisoks/isolinux/
chmod -R u+w /mnt/bootisoks
cd /mnt/bootisoks/isolinux/
#~ nano ks.cfg
cd /mnt/bootisoks
sed -i 's/append\ initrd\=initrd.img/append initrd=initrd.img\ ks\=cdrom:\/ks.cfg/' /mnt/bootisoks/isolinux/isolinux.cfg
mkisofs -untranslated-filenames -o /mnt/boot.iso -b isolinux.bin -c boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -V "CentOS 7 x86_64" -U -r -R -J -T -v isolinux/. .
isohybrid /mnt/boot.iso
implantisomd5 /mnt/boot.iso
#~ ls (boot.iso)
