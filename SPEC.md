# Obelisk Module Specification

A module is any HTTP service that Obelisk can import, route, and manage. The requirements are minimal by design.

---

## Requirements

### 1. Serve HTTP on `$PORT`

Your service must read the `PORT` environment variable and bind its HTTP server to that port.

```go
port := os.Getenv("PORT")  // Obelisk always sets this
http.ListenAndServe(":"+port, handler)
```

Obelisk injects `PORT` at container startup from the value declared in `obelisk.yml`. This overrides any default in your code or your standalone `docker-compose.yml` — the value in `obelisk.yml` always wins when running inside Obelisk. Your fallback default only applies when running the service on its own outside of Obelisk.

The default port is `8080` if `port:` is omitted from `obelisk.yml`. Since each module runs in its own container, there are no port conflicts — all modules could listen on 8080 and Obelisk wouldn't care.

### 2. Respond to HTTP requests

Nginx routes traffic by domain name, not port. Your service just needs to be reachable at `http://<service-name>:$PORT` within the obelisk Docker network.

No TLS required — Obelisk handles termination at the nginx boundary.

---

## Declaring a module in obelisk.yml

```yaml
modules:
  myservice:
    image: registry/myservice:latest  # pre-built image (required for swarm)
    domain: myservice.example.com     # required — the public hostname nginx routes
    port: 8080                        # optional, defaults to 8080
```

Or for local/development builds:

```yaml
modules:
  myservice:
    git_source: ../myservice          # path to a directory with a Dockerfile
    domain: myservice.example.com
    port: 8080                        # optional
```

**Fields:**

| Field | Required | Description |
|-------|----------|-------------|
| `image` | one of `image`/`git_source` | Docker image reference |
| `git_source` | one of `image`/`git_source` | Local path, built by Docker Compose |
| `domain` | yes | Public hostname for nginx routing |
| `port` | no (default: 8080) | Port the service listens on; Obelisk injects this as `PORT` |
| `replicas` | no (default: 1) | Number of replicas (swarm mode only) |
| `env` | no | Additional environment variables |

---

## What Obelisk does for you

- **Injects `PORT`** — you never hardcode a port
- **Generates nginx config** — routes `domain → service:PORT` automatically
- **Network membership** — your container joins the `obelisk` network; service discovery is by name
- **TLS** — not yet implemented, planned

---

## What Obelisk does not require

- A specific language or framework
- A health check endpoint (though recommended)
- Any Obelisk SDK or library
- A particular Dockerfile structure

---

## Migrating an existing service

If your service currently hardcodes its port, the only change needed is to read `PORT` from the environment:

**Go**
```go
// before
http.ListenAndServe(":9100", handler)

// after
port := os.Getenv("PORT")
if port == "" { port = "8080" }
http.ListenAndServe(":"+port, handler)
```

**Node.js**
```js
// before
app.listen(9100)

// after
app.listen(process.env.PORT || 8080)
```

**Python**
```python
# before
app.run(port=9100)

# after
app.run(port=int(os.environ.get("PORT", 8080)))
```

If you also have `PORT: "9100"` in your own `docker-compose.yml` environment section, you can leave it — it acts as a dev fallback when running outside Obelisk and is harmless inside Obelisk because Obelisk's injected value takes precedence.

---

## Service-to-service calls

When one module needs to call another, use the module name as the hostname — Docker DNS resolves it within the `obelisk` network. The port is whatever is declared in `obelisk.yml` for that module.

```
http://agent:9100/api/...
```

Make the peer URL configurable via an env var so it doesn't have to be hardcoded:

```go
agentURL := envOr("OBELISK_AGENT_URL", "http://agent:9100")
```

**Known limitation:** Obelisk does not yet automatically inject peer URLs. If a module's port changes in `obelisk.yml`, any callers that hardcode the URL default will need a matching update. This will be addressed in a future release.

---

## Recommended practices

- **Keep a PORT fallback in your code** for running outside Obelisk: `os.Getenv("PORT")` with a sensible default
- **Expose in your Dockerfile** (`EXPOSE 8080`) for documentation, though it has no functional effect inside Obelisk
- **Log your listening address** on startup so `docker compose logs` gives a clear signal the service is ready
