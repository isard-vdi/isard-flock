# FIXED IMAGE VERSIONS
APP="1.2.2-beta"
HYPERVISOR=$APP
NGINX=$APP
MOSQUITTO="0.1"
GRAFANA="1.1"

# DEFAULT PATH
OUT_PATH=/opt/isard/images

docker image save isard/app:$APP > $OUT_PATH/isard_app:$APP.tar
docker image save isard/hypervisor:$HYPERVISOR > $OUT_PATH/isard_hypervisor:$HYPERVISOR.tar
docker image save isard/nginx:$NGINX > $OUT_PATH/isard_nginx:$NGINX.tar
docker image save isard/mosquitto:$MOSQUITTO > $OUT_PATH/isard_mosquitto:$MOSQUITTO.tar
docker image save isard/grafana:$GRAFANA > $OUT_PATH/isard_grafana:$GRAFANA.tar
