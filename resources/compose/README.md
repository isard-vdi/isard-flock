# Compose for development in isard-flock
git clone https://github.com/<user>/isard /opt/isard/devel-isard
cd /opt/isard/devel-isard
git remote add upstream https://github.com/isard-vdi/isard
git fetch upstream
git fetch
git checkout develop

mkdir -p /opt/isard/devel-isard-flock
git clone https://github.com/isard-vdi/isard-flock /opt/isard/devel-isard-flock

# CHANGE PACEMAKER COMPOSE RESOURCE
### Modify accordingly to your development:
### - /opt/isard/devel-isard-flock/resources/compose/docker-compose.devel.yml
### - /opt/isard/devel-isard-flock/resources/compose/hypervisor.devel.yml
pcs property set maintenance-mode=true
cd /opt/isard/devel-isard-flock/resources/compose/

docker-compose -f docker-compose.yml -f docker-compose.devel.yml config > isard-devel.yml

pcs resource update isard-compose conf="/opt/isard/devel-isard-flock/resources/compose/isard-devel.yml" \
                              env_path="/opt/isard/devel-isard-flock/resources/compose"
docker-compose -f hypervisor.yml -f hypervisor.devel.yml config > hypervisor-devel.yml
pcs resource update isard-compose conf="/opt/isard/devel-isard-flock/resources/compose/hypervisor-devel.yml" \
                              env_path="/opt/isard/devel-isard-flock/resources/compose"

pcs property set maintenance-mode=false
