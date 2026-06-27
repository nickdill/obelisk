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

Obelisk is a lightweight deployment framework for running multiple services on a single server. It manages Docker Swarm or Compose stacks, nginx routing, SSL/TLS, and port allocation — all driven from a single `obelisk.yml` config.

---

## How it works

Define your modules in `obelisk.yml`:

```yaml
version: "0.1"
name: "myapp"
domains:
  local: myapp.localhost
  production: myapp.example.com
modules:
  api:
    image: registry.example.com/api:latest
    domains:
      local: api.localhost
      production: api.example.com
  dashboard:
    git_source: ../dashboard
    domains:
      local: dashboard.localhost
      # A module can answer for several domains at once — list them and nginx
      # routes them all to the same service.
      production:
        - dashboard.example.com
        - www.dashboard.example.com
  site:
    type: static
    domains:
      # The first domain is canonical; it serves content.
      production: www.example.com
    redirects:
      # These hostnames 301 to the canonical domain instead of serving content.
      # Useful for apex→www (or www→apex) on static sites, which can't redirect
      # themselves. Flip the two keys to make the apex canonical instead.
      production: example.com
```

A module's per-environment domain may be a single hostname (as `api` above) or a
list of hostnames (as `dashboard`). Single-hostname configs are unchanged.

The optional `redirects` key mirrors `domains` (scalar or list, per environment).
Listed hostnames issue a `301` to the module's canonical domain — the first entry
under `domains` for that environment — rather than serving content. Omit it to
serve every hostname identically (the default).

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

## Environments

Obelisk supports per-environment domain configuration via the `OBELISK_ENV` variable. Each module declares a `domains:` map keyed by environment name — Obelisk uses the active environment to determine which domain to route. Each environment entry may be a single hostname or a list of hostnames, all routed to the same module.

```sh
cp .env.example .env
# Set OBELISK_ENV=local (default) or production, staging, etc.
```

In dev mode, services are started using Docker Compose profiles matching the active environment.

---

## SSL/TLS

Obelisk handles TLS termination at the nginx boundary using Let's Encrypt. To enable:

```sh
OBELISK_SSL=true
OBELISK_SSL_EMAIL=you@example.com
OBELISK_SSL_STAGING=0  # set to 1 for Let's Encrypt staging (rate-limit safe)
```

On first run, Obelisk bootstraps certificates for all configured domains. A certbot sidecar container handles automatic renewal. If ACME validation fails, Obelisk falls back to a self-signed certificate so nginx can still start.

---

## Module requirements

A module is any HTTP service that Obelisk can import, route, and manage:

- **Listen on `$PORT`** — Obelisk injects this at container startup (defaults to 8080)
- **No TLS needed** — Obelisk terminates SSL at the nginx boundary
- **Any language or framework** — no SDK or specific Dockerfile structure required

---

## Requirements

- Docker (with Swarm initialized for `run.sh`)
- [`yq`](https://github.com/mikefarah/yq)
