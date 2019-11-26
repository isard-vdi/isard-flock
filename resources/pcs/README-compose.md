# ra-docker-compose

docker-compose for resource agent

* Pacemaker config setting

```
primitive res_compose_service ocf:heartbeat:compose \
        params conf="/opt/compose/docker-compose.yml" \
        params env_path="/opt/compose" \
        params force_kill="true" \
        op start interval="0" timeout="300" \
        op stop interval="0" timeout="300" \
        op monitor interval="60" timeout="60"
```

Put it in /usr/lib/ocf/resource.d/
