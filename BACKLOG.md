# Backlog

## ~~Static module deployment to remote servers~~ (resolved)

Resolved via image delivery + a shared volume. Static modules now publish to a
busybox "artifact image" (`obelisk publish` builds assets locally and packages
`dist/` at `/static`). On the server, `.obelisk/scripts/sync-static.sh` pulls the
image and extracts the assets into the shared `obelisk_static` named volume,
which a single nginx serves from `/obelisk/static/<name>/`. Both the CLI path
(`obelisk deploy`, via the agent) and the manual path (`obelisk run` after
editing `obelisk.yml`) converge on `sync-static.sh`. Local dev still bind-mounts
the built dir directly. A missing site now degrades to a per-host 404 instead of
crashing the whole webserver.

## SSL init should skip non-public domains

`obelisk run` with `OBELISK_SSL=true` attempts to request Let's Encrypt certificates for all configured domains, including `.localhost` domains that can never pass ACME validation. The SSL init script should detect non-public TLDs (e.g. `.localhost`, `.local`, `.test`) and skip certificate requests for them, or only attempt SSL for domains in the production environment.

## SSL init `fix_certbot_permissions` fails silently

`fix_certbot_permissions()` in `.obelisk/ssl/init-ssl.sh` swallows all errors
(`2>/dev/null || true`). The certbot container writes `conf/{live,archive,renewal}`
files as root, and this helper is what chowns them back to the host user. When it
silently fails (e.g. the `alpine:3.20` image can't be pulled on a locked-down prod
host), the breakage doesn't surface until a later host-side `rm` hits
`Permission denied` — which is how this was discovered on prod
(`rm: cannot remove '.obelisk/certbot/conf/archive/<domain>': Permission denied`).

The immediate `rm` was made robust by deleting via a root container instead of on
the host (committed). Remaining work: make `fix_certbot_permissions` warn loudly
(or fail) when the chown doesn't succeed, so a broken certbot-permissions state is
reported at the source instead of three steps downstream. Held off initially since
it's a behavior change beyond the reported bug.
