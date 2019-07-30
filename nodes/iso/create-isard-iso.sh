rm -rf ./bootisoks
umount ./iso
mkdir ./iso
if [[ ! -f CentOS-7-x86_64-Minimal-1810.iso ]]; then
	wget http://ftp.uma.es/mirror/CentOS/7.6.1810/isos/x86_64/CentOS-7-x86_64-Minimal-1810.iso
fi
mount -o loop ./CentOS-7-x86_64-Minimal-1810.iso  ./iso
mkdir ./bootisoks
cp -r ./iso/* ./bootisoks/
umount ./iso

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

cp ks.cfg ./bootisoks/isolinux/
chmod -R u+w ./bootisoks
cd ./bootisoks
sed -i 's/append\ initrd\=initrd.img/append initrd=initrd.img\ ks\=cdrom:\/ks.cfg/' ./isolinux/isolinux.cfg
mkisofs -untranslated-filenames -o ../isard-flock.iso -b isolinux.bin -c boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -V "CentOS 7 x86_64" -U -r -R -J -T -v isolinux/. .
cd ..
isohybrid isard-flock.iso
implantisomd5 isard-flock.iso
