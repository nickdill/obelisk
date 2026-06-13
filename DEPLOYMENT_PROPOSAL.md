# Obelisk Deployment Proposal

## The Core Question

> *"Can we create one image that already has all child images pulled so prod just pulls the one?"*

No. Docker does not work that way, and the workaround that does exist (bundling images as tar files inside a parent image and loading them at entrypoint) is a maintenance nightmare and inflates your image size by the sum of all modules. It exists in niche airgapped scenarios and should not be your default path.

The good news: **you don't need it.** The real problem is pull time and registry auth, not the inability to pre-bundle. Docker's layer cache solves the pull-time problem, and IAM solves the auth problem. Both are straightforward.

---

## Why Pull-on-Deploy Is the Right Model

When your Obelisk agent runs `docker compose up -d` with a given module image, Docker only pulls layers it doesn't already have locally. After the first deploy, subsequent deploys of the same module are near-instant because the layers are cached on the host. The only slow deploy is the first one, or when a module has grown significantly.

This means the flow that `obelisk publish` → `obelisk deploy` implies is exactly correct:

```
Developer machine         Registry (ECR)          Obelisk Server
      │                        │                        │
      │  docker build + tag    │                        │
      │──────────────────────► │                        │
      │  docker push           │                        │
      │──────────────────────► │                        │
      │                        │                        │
      │  obelisk deploy        │                        │
      │────────────────────────┼──────────────────────► │
      │                        │  docker pull (delta)   │
      │                        │ ◄────────────────────── │
      │                        │                        │  generate-compose.sh
      │                        │                        │  generate-nginx.sh
      │                        │                        │  docker compose up -d
      │                        │                        │  nginx -s reload
      │                        │   streaming log output │
      │ ◄──────────────────────┼──────────────────────── │
```

The deploy payload from CLI to agent is just metadata (module name, image ref, config). The server handles auth and pull itself. The CLI streams the output back.

---

## Production Registry Authentication

This is the gap that needs filling. The server must authenticate to your registry before it can pull private images. There are two clean paths depending on your hosting model.

### Path A — EC2 with IAM Instance Profile (Recommended for AWS)

Attach an IAM role to the EC2 instance at provisioning time with the following inline policy:

```json
{
  "Effect": "Allow",
  "Action": [
    "ecr:GetAuthorizationToken",
    "ecr:BatchCheckLayerAvailability",
    "ecr:GetDownloadUrlForLayer",
    "ecr:BatchGetImage"
  ],
  "Resource": "*"
}
```

Add this to the cloud-init script in `PLAN_SERVER_PROVISIONING.md §5`:

```sh
# In .obelisk/run.sh — executed before docker compose up
aws ecr get-login-password --region "${AWS_REGION}" \
  | docker login --username AWS --password-stdin \
    "${AWS_ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com"
```

The `aws` CLI is available on Ubuntu 24.04 by default. With the instance profile, this never needs stored credentials — the role provides them. Re-run this login before every deploy invocation (the token is valid 12 hours but re-running is cheap and safe).

This is the cleanest production path. No secrets stored anywhere.

### Path B — Stored Credentials (Non-AWS or Bring-Your-Own Server)

For servers that aren't EC2, or any registry that isn't ECR, Docker's credential store is the right mechanism. The initial `obelisk server new` setup or `obelisk init` should write a `~/.docker/config.json` (or use `docker-credential-secretservice` on the host) with the registry credentials. Your `.obelisk/run.sh` then calls `docker login` once.

Store the registry credentials in `.env` and pull them in `run.sh`:

```sh
# .env (gitignored, written at provision time)
REGISTRY_HOST=registry.example.com
REGISTRY_USER=deployer
REGISTRY_TOKEN=<token>
```

```sh
# .obelisk/run.sh
docker login "${REGISTRY_HOST}" \
  --username "${REGISTRY_USER}" \
  --password "${REGISTRY_TOKEN}"
```

This is what the `OBELISK_AUTHORIZED_KEY` pattern in your current `.env.example` already sets up — extend the same pattern for registry credentials.

---

## What `obelisk publish` Needs to Build

`cmd/publish.go` is the key missing piece. It closes the loop from code to deployment. The spec is clear:

```
obelisk publish [--tag <tag>] [--registry <url>]
```

1. Read `obelisk.yml` for `name:` and `image:` (the image field sets the registry path)
2. Determine the tag: default to `latest`, or `--tag`, or the current git SHA (`git rev-parse --short HEAD`)
3. `docker build -t <image>:<tag> .` — stream output
4. If ECR: run `aws ecr get-login-password | docker login ...` as a preflight step
5. `docker push <image>:<tag>` — stream output
6. Print the final image ref so it can be fed into `obelisk deploy` or a CI pipeline

Git SHA tags are strongly recommended over `latest` for production. They give you a clear audit trail and make rollback trivial (just `obelisk deploy --image <sha>` with a prior ref). `latest` is fine for development convenience but creates ambiguity in prod because you lose traceability of what's actually running.

The obelisk.yml `image:` field should hold the full registry path without the tag:

```yaml
# obelisk.module.yml
image: 123456789.dkr.ecr.us-east-2.amazonaws.com/my-module
```

Then publish appends the tag and deploy sends the full ref.

---

## The Deployment Agent Gap

The current `obelisk deploy` implementation (`cmd/deploy.go`) sends `{"module": cfg.Name}` to `POST /v1/deploy`. For the full flow to work, the agent (`../obelisk-agent`) needs to:

1. Receive the deploy request with module name (and optionally a specific image tag)
2. Look up the module in `obelisk.yml` to find the `image:` field
3. Run ECR login (or generic docker login) using credentials from `.env`
4. `docker pull <image>:<tag>`
5. Run `generate-compose.sh` and `generate-nginx.sh` (or equivalent Go logic)
6. `docker compose up -d <module>` (rolling restart of just the affected service, not the whole stack)
7. `nginx -s reload`
8. Stream all output back to the CLI

Two things worth deciding before implementing:

**Partial vs. full restart**: `docker compose up -d <module>` only restarts the changed service, leaving all other modules untouched. This should be the default. A `--full` flag can trigger `docker compose up -d` for the whole stack when needed (e.g., after changing the base compose file).

**Image tag in the deploy payload**: Right now `cmd/deploy.go` only sends the module name. You should also send the image tag so the server knows exactly what to pull. Otherwise the server has to guess (pull `latest`, which is fragile). The deploy API should accept `{"module": "my-module", "image": "...ecr.../my-module:abc1234"}`.

---

## On the Question of Kubernetes

**Not yet. Probably not for a long time.**

Here is the honest assessment of when k8s is justified:

| Condition | Your current state |
|---|---|
| Dozens of services needing independent scaling | No — you have a few modules per Obelisk |
| Multiple servers requiring coordinated rollouts | Obelisk is single-server by design (for now) |
| A dedicated DevOps team to operate it | No |
| Traffic patterns that demand horizontal pod autoscaling | Not demonstrated |
| CI/CD pipelines already built around k8s tooling | No — you're building your own |

Kubernetes would eliminate everything you have built and replace it with a system that requires a full-time engineer to operate. You would be writing Helm charts and managing node pools instead of shipping features.

The right progression is:

1. **Now**: Docker Compose + nginx on a single EC2 (what you have)
2. **If you need multi-server**: Docker Swarm — same Compose files, built-in service distribution, zero new mental model
3. **If you need true container orchestration at scale**: That is when k8s is justified, and by that point you will have the team and traffic to warrant it

Obelisk is already more elegant than what most small-to-medium teams run. Finish the `publish → deploy` loop before optimizing the infrastructure layer.

---

## The Production-Ready Deployment Checklist

These are the concrete gaps between the current architecture and a fully working production deployment:

### In `obelisk` (this repo)

- [ ] **`.obelisk/run.sh`** (generated by `obelisk init`): add ECR login step before `docker compose up`. Gate it behind an `AWS_REGION` env check so it's skipped for non-ECR setups.
- [ ] **`.obelisk/scripts/generate-nginx.sh`**: add SSL block generation for production (the current template only generates HTTP). Production nginx needs `listen 443 ssl` with certbot cert paths. The local override (via `obelisk.local.yml`) should stay HTTP-only.
- [ ] **`.env.example`**: add `AWS_REGION` and `REGISTRY` entries since they're referenced in `run.sh`

### In `obelisk-cli`

- [ ] **`obelisk publish`**: implement as described above
- [ ] **`cmd/deploy.go`**: add `image` field to the deploy payload so the server knows the exact tag to pull

### In `obelisk-agent`

- [ ] **`POST /v1/deploy` handler**: implement the pull → generate → restart → reload sequence
- [ ] **Registry login**: read from `.env`, run `docker login` before pull

### In the cloud-init template (`PLAN_SERVER_PROVISIONING.md §5`)

- [ ] **IAM instance profile**: the `obelisk server new` AWS provider should attach an instance profile with ECR read permissions at launch time
- [ ] **ECR login in `run.sh`**: confirm the generated script runs ECR auth before the first `docker compose up`

---

## Recommended Immediate Order

The bottleneck is not the infrastructure layer — it is the missing `publish → deploy` pipeline. Everything else (k8s, pre-bundled images, complex auth) is downstream of having that loop close cleanly.

1. Implement `obelisk publish` (builds image, pushes to ECR, prints the full image ref)
2. Update the deploy API payload to include the image ref
3. Implement the agent-side deploy handler (pull → compose → reload)
4. Add ECR login to `run.sh` (generated by `obelisk init`) gated on `AWS_REGION`
5. Test the full loop: `obelisk publish && obelisk deploy` on a live EC2 instance

Once that loop works end-to-end, the deployment model is sound and you can layer in the provisioning automation (`obelisk server new`) on top of it.
