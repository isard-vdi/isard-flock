# linstor-server

wget https://www.linbit.com/downloads/linstor/linstor-server-$1.tar.gz
rpmbuild -tb linstor-server-1.2.1.tar.gz
mv /root/rpmbuild/RPMS/noarch/linstor-* /RPMS
