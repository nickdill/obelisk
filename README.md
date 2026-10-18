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

## Quick reference: ship a new service

Two kinds of directory use `obelisk.yml`, and the `type:` field tells them apart:

| | Server project | Module repo |
|---|---|---|
| What it is | The stack that runs on a server: nginx, SSL, and a list of modules | One app (your service) |
| `type:` | `server` | `module` (container) or `static` (built files) |
| Created by | `obelisk new <name>` or `obelisk init` | `obelisk init --module` |
| Lives | On the server (and on your laptop for local runs) | In the service's own repo |

Requirements: Docker, [`yq`](https://github.com/mikefarah/yq), and the `obelisk` CLI (macOS and Linux):

```sh
curl -fsSL https://raw.githubusercontent.com/nickdill/obelisk-cli/main/install.sh | bash
```

### 1. Make your service a module

From the root of the service's repo (or the subdirectory that gets deployed, such as `site/` or `cloud/` in a monorepo):

```sh
obelisk init --module
```

This writes three files and never overwrites an existing `obelisk.yml`:

- `obelisk.yml`: the module's identity and build config
- `.obelisk/dev.sh`: the command that starts the service for local development
- `.obelisk/build.sh`: the production build step

Then edit them for the kind of service you have.

**Container service** (API, web app, anything long-running). It needs a `Dockerfile`, must listen on `$PORT`, and needs no TLS:

```yaml
# obelisk.yml
version: "0.1"
name: "shipmade-cloud"        # must match the module's key in the server's obelisk.yml
type: module
image: ghcr.io/nickdill/shipmade-cloud
port: 8080
platform: linux/amd64         # match your server's CPU (use linux/arm64 for Graviton)
```

**Static site** (compiled HTML/JS). It has no running container. The built files are served by the shared nginx:

```yaml
# obelisk.yml
version: "0.1"
name: "shipmade-site"
type: static
image: ghcr.io/nickdill/shipmade-site   # artifact image that carries the files
dist: dist                              # build output directory
build: npm run build                    # run locally at publish time
```

### 2. Run it locally

There are two ways, depending on what you want to test.

**Just the app.** From the module repo, run `obelisk dev`. It runs your `.obelisk/dev.sh`, so put your normal dev command there (`npm run dev`, `go run .`, `docker compose up`, and so on). This does not involve nginx or routing.

**Behind real routing.** To check domains, nginx and the full stack, add the module to a server project (your Obelisk checkout or one made with `obelisk new`) and start that:

```yaml
# obelisk.yml in the server project
modules:
  shipmade-cloud:
    git_source: ../shipmade/cloud     # path to the module repo; built from its Dockerfile
    port: 8080
    domains:
      local: cloud.shipmade.localhost
```

```sh
obelisk dev            # add --build to rebuild images first
```

nginx answers on port 80 (or `OBELISK_HTTP_PORT`), so browse to `http://cloud.shipmade.localhost`, not to the module's own port. For a static module, set `type: static` plus `git_source`, and `obelisk dev` serves its built `dist/` directly.

### 3. Deploy it

Production is a Docker Swarm stack on one server, managed over signed HTTPS by `obelisk-agent`. Your laptop never SSHes in once setup is done.

```
 laptop                       registry                    server (Docker Swarm stack "obelisk")
┌──────────────────┐         ┌────────────┐              ┌──────────────────────────────────────────┐
│ obelisk publish ─┼─ push ─▶│ ghcr.io /  │◀──── pull ───┤ nginx :80/:443 ── routes by domain ──┐   │
│                  │         │ ECR        │              │   + certbot (Let's Encrypt renewal)  │   │
│ obelisk deploy  ─┼─ signed HTTPS ───────────────────▶ │ obelisk-agent (/_obelisk/*, internal)│   │
└──────────────────┘                                    │        │ docker.sock                 ▼   │
                                                        │        └─▶ module services (obelisk_<name>)│
                                                        │            static sites: shared volume   │
                                                        └──────────────────────────────────────────┘
```

- **nginx** is the only public entry point. It matches the request's hostname against each module's `domains:` entry for the active `OBELISK_ENV` and forwards to that service.
- **Container modules** run as Swarm services named `obelisk_<name>`. Obelisk injects `PORT`.
- **Static modules** ship as small artifact images. The agent extracts them into a shared volume that one nginx serves, so there's no container per site.
- **`obelisk-agent`** receives deploy requests, checks the ED25519 signature against its authorized keys, and runs the pull and service update using the host's Docker socket.
- **Images come from a registry.** Production needs an `image:`. A `git_source:` module only works in local dev and is skipped on the server.

**One-time server setup**

1. Provision a Linux host with Docker (see `obelisk-cli/_docs/ec2_setup.md` for EC2). Open ports 80 and 443.
2. On the host, install the CLI, then put the server project there (`obelisk init` in an empty directory, or clone your project repo) and fill in `.env`:
   ```sh
   OBELISK_ENV=production
   OBELISK_AUTHORIZED_KEY="obk1_... you@laptop"   # from `obelisk identity` on your laptop
   OBELISK_SSL=true
   OBELISK_SSL_EMAIL=you@example.com
   REGISTRY_HOST=ghcr.io
   REGISTRY_USER=<user>
   REGISTRY_TOKEN=<token with read:packages>
   ```
3. Run the stack once with `obelisk run`. It initializes Swarm if needed. Make sure `obelisk-agent` is one of the modules (see the `obelisk-agent` repo).
4. From your laptop, register the server: `obelisk server add prod https://<server-domain>`.

**Add the service to the server (once per service).** `obelisk deploy` updates a service that already exists, so the first time you must declare it in the *server's* `obelisk.yml` and start it. Use the same key as the module's `name:`:

```yaml
# obelisk.yml on the server
domains:
  production: obelisk.example.com
modules:
  shipmade-cloud:
    image: ghcr.io/nickdill/shipmade-cloud:latest
    port: 8080
    domains:
      production: api.shipmade.dev
    environment:                 # note: `environment`, not `env`
      DATABASE_URL: postgres://...
  shipmade-site:
    type: static
    image: ghcr.io/nickdill/shipmade-site:latest
    domains:
      production: www.shipmade.dev
    redirects:
      production: shipmade.dev
```

Point the DNS records for those hostnames at the server, publish an image tagged `latest` so the reference resolves (`obelisk publish --tag latest`), then run `obelisk run` on the server. This regenerates the nginx config, requests certificates and starts the service.

**Every deploy after that**, from the module repo on your laptop:

```sh
obelisk publish                      # build and push (tag defaults to the git SHA); needs REGISTRY_* in the module's .env
obelisk deploy --image ghcr.io/nickdill/shipmade-cloud:<tag>   # pull that exact image and update the service
obelisk deploy --server prod         # only needed if more than one server is registered
```

For a static module, `obelisk publish` builds `dist/` and packages it, and a plain `obelisk deploy` extracts the files. For a container module, `obelisk deploy` without `--image` instead re-runs the server's `run.sh`, a full stack redeploy that pulls whatever the server's `obelisk.yml` references. Deploy output streams live, and only one deploy can run at a time on a server (a second gets a conflict error).

**Check on it**

```sh
obelisk list                         # state and health of every module on every registered server
obelisk scale shipmade-cloud 2       # change replica count
obelisk logs shipmade-cloud          # run on the server, since it reads Swarm service logs
```

To control who may deploy, authorize a teammate with `obelisk allow <obk1_key> --name "Alice" --server prod` and remove access with `obelisk revoke <fingerprint> --server prod`.

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

---

## Related repositories

Obelisk is split across several repos, each with one job. Everything lives under `github.com/nickdill/` unless noted.

### Core

| Repo | Role | Status |
|---|---|---|
| [`obelisk`](https://github.com/nickdill/obelisk) | **This repo.** The base project: Docker Compose + nginx + Certbot stack, `obelisk.yml` config, and the generator scripts that wire modules together. Self-contained, so it runs without the CLI. | Active |
| [`obelisk-cli`](https://github.com/nickdill/obelisk-cli) | The `obelisk` command-line tool (Go). Scaffolds projects (`obelisk new`/`init`), runs them locally, builds modules and deploys. Talks to servers only through `obelisk-agent`. | Active |
| [`obelisk-agent`](https://github.com/nickdill/obelisk-agent) | Small Go service that runs on each deployed server. nginx proxies `/_obelisk/*` to it, and it accepts ED25519-signed requests from the CLI to deploy, report status and manage authorized keys. No SSH or passwords. Optional. | Active |

### Modules

Modules are apps that an Obelisk project hosts. Add one to `obelisk.yml` and it gets routed.

| Repo | Role | Status |
|---|---|---|
| [`obelisk-module-dashboard`](https://github.com/nickdill/obelisk-module-dashboard) | Static React/TypeScript management UI (served at `/dashboard`). Lets you manage servers and projects imported from `obelisk.yml`. Also a test module for the module system. | In progress |
| `obelisk-debug` | Example module: a static debug console (log forwarding, analytics) you can add to any Obelisk app. Local only, not yet on GitHub. | Prototype |
| [`obelisk-module-template`](https://github.com/nickdill/megalisk-module-template) | Starter template for a new module. Still uses the old `megalisk.module.yml` naming and the old `megalisk-module-template` remote name. | Needs rename |

### Tooling and infrastructure

| Repo | Role | Status |
|---|---|---|
| [`obelisk-dev-env`](https://github.com/nickdill/obelisk-dev-env) | Docker image for user development environments, published to `ghcr.io/nickdill/obelisk-dev-env`. | Active |
| `obelisk-server` | Minimal sample `obelisk.yml` (one nginx module) with compose files. A scratch project for trying out a server, not a product. Local only. | Scratch |

### Planned products

| Repo | Role | Status |
|---|---|---|
| [`obelisk-dev`](https://github.com/nickdill/obelisk-dev) | Managed cloud dev environment with Claude Code in the browser. Its README says it is out of date. | Early concept |
| `obelisk-ci` | Self-hostable CI/CD: push to Obelisk, build, test and deploy, with pinned versions and rollback. Only docs so far, and it is deliberately deferred until the core is stable. Local only. | Planning |

### Megalisk (predecessor)

Obelisk was previously called Megalisk. These repos predate the rename and are not part of Obelisk:

| Repo | Role |
|---|---|
| [`megalisk-cli`](https://github.com/nickdill/megalisk-cli) | The original `mega` CLI and `megalisk.yml` format. Superseded by `obelisk-cli`. |
| [`megalisk`](https://github.com/nickdill/megalisk) | Rails 8 dashboard that tracks a fleet of servers and deployed apps. The dashboard half of the old ecosystem. |
| `megalisk-local` | Early goal and design notes only. |

### How they fit together

```
 laptop                                     server
┌─────────────┐   signed HTTPS    ┌──────────────────────────────────────┐
│ obelisk-cli │ ────────────────▶ │ nginx ─▶ obelisk-agent  (/_obelisk/) │
└─────────────┘                   │   │                                  │
       │ obelisk new / init       │   ├─▶ module: dashboard              │
       ▼                          │   ├─▶ module: debug                  │
┌─────────────┐                   │   └─▶ your apps                      │
│  obelisk    │ ── deployed as ─▶ │  (this repo: compose + nginx + SSL)  │
└─────────────┘                   └──────────────────────────────────────┘
```
