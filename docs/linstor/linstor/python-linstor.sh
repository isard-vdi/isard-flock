# linstor-client

wget https://www.linbit.com/downloads/linstor/python-linstor-$1.tar.gz
tar xvf python-linstor-$1.tar.gz
cd python-linstor-$1
make rpm
mv /python-linstor-$1/dist/python-linstor-$1*.noarch.rpm /RPMS
