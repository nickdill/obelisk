```
 ██████╗ ██████╗ ███████╗██╗     ██╗███████╗██╗  ██╗
██╔═══██╗██╔══██╗██╔════╝██║     ██║██╔════╝██║ ██╔╝
██║   ██║██████╔╝█████╗  ██║     ██║███████╗█████╔╝ 
██║   ██║██╔══██╗██╔══╝  ██║     ██║╚════██║██╔═██╗ 
╚██████╔╝██████╔╝███████╗███████╗██║███████║██║  ██╗
 ╚═════╝ ╚═════╝ ╚══════╝╚══════╝╚═╝╚══════╝╚═╝  ╚═╝
```

> [!WARNING]
> **This project is under active development.** Interfaces, config formats, and behavior will change without notice. Not yet suitable for production use.

Obelisk is a lightweight deployment framework for running multiple services on a single server. It manages Docker Swarm or Compose stacks, nginx routing, and port allocation — all driven from a single `obelisk.yml` config.

---

## How it works

Define your modules in `obelisk.yml`:

```yaml
version: "0.1"
name: "myapp"
modules:
  api:
    image: registry.example.com/api:latest
    domain: api.localhost
  dashboard:
    git_source: ../dashboard
    domain: dashboard.localhost
```

Then bring everything up:

```sh
# Local dev (builds from source, hot-reload friendly)
sh .obelisk/dev.sh

# Swarm deploy (requires pre-built images)
sh .obelisk/run.sh

# Tear down
sh .obelisk/stop.sh
```

Obelisk handles port allocation, generates the Compose files, and configures nginx to route traffic by domain.

---

## Requirements

- Docker (with Swarm initialized for `run.sh`)
- [`yq`](https://github.com/mikefarah/yq)

---

## Docs

See [`docs/`](./docs/) for setup guides, the spec, and deployment notes.
