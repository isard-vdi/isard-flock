# linstor-client

wget https://www.linbit.com/downloads/linstor/linstor-client-$1.tar.gz
tar xvf linstor-client-$1.tar.gz
cd linstor-client-$1
make rpm
mv /linstor-client-$1/dist/linstor-client-$1*.noarch.rpm /RPMS
