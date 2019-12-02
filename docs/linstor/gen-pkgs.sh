#https://www.linbit.com/en/drbd-community/drbd-download/#drbddownload
#docker-compose -f build.yml build
docker run -ti -v /opt/RPMS:/RPMS isard/pkgbuild /bin/sh -c "/linstor-server.sh 1.2.1"
docker run -ti -v /opt/RPMS:/RPMS isard/pkgbuild /bin/sh -c "/python-linstor.sh 1.0.7"
docker run -ti -v /opt/RPMS:/RPMS isard/pkgbuild /bin/sh -c "/linstor-client.sh 1.0.6"
