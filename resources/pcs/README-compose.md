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
```
pcs resource create isard-compose ocf:heartbeat:compose \
        conf="/opt/isard-flock/resources/compose/docker-compose.yml" \
        env_path="/opt/isard-flock/resources/compose" \
        force_kill="true" \
        op start interval=0s timeout=300s \
        op stop interval=0 timeout=300s \
        op monitor interval=60s timeout=60s
```

docker-compose -f /opt/isard-flock/resources/compose/docker-compose.yml

Put it in /usr/lib/ocf/resource.d/



[root@if2 ~]# pcs resource describe compose
Assumed agent name 'ocf:heartbeat:compose' (deduced from 'compose')
ocf:heartbeat:compose - Docker container resource agent.

The docker HA resource agent creates and launches a docker container
based off a supplied docker image. Containers managed by this agent
are both created and removed upon the agent's start and stop actions.

Resource options:
  image (required): The docker image to base this container off of.
  name: The name to give the created container. By default this will be that resource's instance name.
  allow_pull: Allow the image to be pulled from the configured docker registry when the image does not exist locally. NOTE, this can drastically increase the time required to start the
              container if the image repository is pulled over the network.
  run_opts: Add options to be appended to the 'docker run' command which is used when creating the container during the start action. This option allows users to do things such as setting a
            custom entry point and injecting environment variables into the newly created container. Note the '-d' option is supplied regardless of this value to force containers to run in
            the background. NOTE: Do not explicitly specify the --name argument in the run_opts. This agent will set --name using either the resource's instance or the name provided in the
            'name' argument of this agent.
  run_cmd: Specify a command to launch within the container once it has initialized.
  mount_points: A comma separated list of directories that the container is expecting to use. The agent will ensure they exist by running 'mkdir -p'
  monitor_cmd: Specify the full path of a command to launch within the container to check the health of the container. This command must return 0 to indicate that the container is healthy. A
               non-zero return code will indicate that the container has failed and should be recovered. If 'docker exec' is supported, it is used to execute the command. If not, nsenter is
               used. Note: Using this method for monitoring processes inside a container is not recommended, as containerd tries to track processes running inside the container and does not
               deal well with many short-lived processes being spawned. Ensure that your container monitors its own processes and terminates on fatal error rather than invoking a command
               from the outside.
  force_kill: Kill a container immediately rather than waiting for it to gracefully shutdown
  reuse: Allow the container to be reused once it is stopped. By default, containers get removed once they are stopped. Enable this option to have the particular one persist when this
         happens.
  query_docker_health: Query the builtin healthcheck of docker (v1.12+) to determine health of the container. If left empty or set to false it will not be used. The healthcheck itself has to
                       be configured within docker, e.g. via HEALTHCHECK in Dockerfile. This option just queries in what condition docker considers the container to be and lets ocf do its
                       thing accordingly. Note that the time a container is in "starting" state counts against the monitor timeout. This is an additional check besides the standard check for
                       the container to be running, and the optional monitor_cmd check. It doesn't disable or override them, so all of them (if used) have to come back healthy for the
                       container to be considered healthy.

Default operations:
  start: interval=0s timeout=90s
  stop: interval=0s timeout=90s
  monitor: interval=30s timeout=30s

