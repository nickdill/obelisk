1. Initialize Docker Swarm (one-time)
  For multi-node swarms, set OBELISK_ADVERTISE_ADDR in .env first:
    OBELISK_ADVERTISE_ADDR=<MANAGER-IP>:2377

  Then run setup (or docker swarm init --advertise-addr <MANAGER-IP>:2377 directly):
    sh .obelisk/setup.sh

  2. Build images first (swarm can't build from git_source/context — images must be pre-built and available)
  docker compose -f docker-compose.yml -f docker-compose.override.yml build

  3. Deploy the stack using the swarm compose file
  docker stack deploy -c docker-compose.yml -c docker-compose.swarm.yml obelisk

  The key difference: docker-compose.swarm.yml switches the network driver from bridge to overlay, which is
  required for swarm mode. The docker-compose.override.yml is intentionally excluded from swarm deploys
  because git_source builds aren't supported in swarm — you'd need pre-built images referenced by image:
  instead.

  To check status:
  docker stack services obelisk
  docker stack ps obelisk

  To tear down:
  docker stack rm obelisk

  Key limitation to be aware of: Your obelisk.yml currently uses git_source for both modules, but swarm
  requires image: references to a registry. The override.yml builds those locally for dev, but for a true
  swarm production test you'd need to docker build && docker tag your modules as named images first, then
  reference them via image: in the compose file or obelisk.yml. That's the gap the obelisk publish command is
  meant to close (per DEPLOYMENT_PROPOSAL.md).
