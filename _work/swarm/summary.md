# Swarm Debugging Summary

**Goal:** MacBook Pro (Docker Desktop, `192.168.0.124`) acts as swarm manager. Raspberry Pi joins as a worker.

---

## Current State

- Swarm is initialized on the Mac with `OBELISK_ADVERTISE_ADDR=192.168.0.124` and `OBELISK_LISTEN_ADDR=192.168.64.2:2377`
- `nc -zv 192.168.0.124 2377` from the Pi now returns **Connection refused** (previously hung — network path is open)
- Port 2377 is not yet reachable from the Pi

---

## What We Learned

### Problem 1: `OBELISK_ADVERTISE_ADDR` was set to a URL

`.env` had `OBELISK_ADVERTISE_ADDR=http://nickdill.local`. Docker's `--advertise-addr` expects a bare IP or interface name — no `http://` scheme, no hostname. Error:

> advertise address must be a non-zero IP address or network interface (with optional port number)

**Fix:** Changed to `OBELISK_ADVERTISE_ADDR=192.168.0.124`.

---

### Problem 2: Docker Desktop's VM doesn't have the Mac's LAN IP

The Mac's `en0` IP (`192.168.0.124`) is not present inside the Docker Desktop Linux VM. Docker rejected it as an unknown address:

> must specify a listening address because the address to advertise is not recognized as a system address, and a system's IP address to use could not be uniquely identified

Docker Desktop's VM network interfaces (from `docker run --rm --net=host alpine ip addr show`):

| Interface | IP | Notes |
|---|---|---|
| `eth0` | `192.168.65.3/24` | Docker Desktop internal |
| `eth1` | `192.168.64.2/24` | vpnkit bridge — used for port forwarding to Mac host |
| `docker0` | `172.17.0.1/16` | default bridge |

**Fix:** Added `OBELISK_LISTEN_ADDR=192.168.64.2:2377` so Docker listens on a valid VM interface (`eth1`) while advertising the Mac's real LAN IP to workers. Updated `setup.sh` to pass `--listen-addr "$OBELISK_LISTEN_ADDR"` alongside `--advertise-addr`.

---

### Problem 3: Docker Desktop does not auto-forward swarm ports to the Mac's LAN interface

Docker Desktop forwards published *container* ports (via `-p`), but does **not** automatically expose the Docker daemon's own listening ports (2377, 7946, 4789) on the Mac's external network interface.

Even with Docker listening on `eth1` (`192.168.64.2:2377`), workers hit `Connection refused` on `192.168.0.124:2377` because nothing bridges those two networks.

**Status: UNRESOLVED.** The proposed fix is macOS `pf` port forwarding — see next section.

---

## Proposed Fix: macOS pf Port Forwarding

Forward swarm ports from the Mac's LAN interface into the Docker Desktop VM's `eth1`:

```sh
# TCP: swarm management (2377) and node gossip (7946)
sudo sh -c 'echo "rdr pass on en0 proto tcp from any to 192.168.0.124 port {2377,7946} -> 192.168.64.2" >> /etc/pf.conf && pfctl -f /etc/pf.conf -e'

# UDP: node gossip (7946) and overlay VXLAN (4789)
sudo sh -c 'echo "rdr pass on en0 proto udp from any to 192.168.0.124 port {7946,4789} -> 192.168.64.2" >> /etc/pf.conf && pfctl -f /etc/pf.conf'
```

**Not yet tested.** After applying, verify with:
```sh
nc -zv 192.168.0.124 2377   # from the Pi
```

### Caveats with pf approach

- `192.168.64.2` (Docker VM's `eth1`) can change if Docker Desktop restarts — pf rules would need to be updated
- `en0` assumed to be the LAN interface — verify with `networksetup -listallhardwareports`
- Rules in `/etc/pf.conf` survive reboot; verify post-reboot with `sudo pfctl -sr`

---

## Current .env (swarm-relevant fields)

```sh
OBELISK_ADVERTISE_ADDR=192.168.0.124
OBELISK_LISTEN_ADDR=192.168.64.2:2377
```

## Current setup.sh swarm init command

```sh
docker swarm init --advertise-addr "$OBELISK_ADVERTISE_ADDR" --listen-addr "$LISTEN_ADDR"
```

(`LISTEN_ADDR` defaults to `0.0.0.0:2377` if `OBELISK_LISTEN_ADDR` is unset.)

---

## Next Steps

1. Apply the `pf` rules above and retest `nc -zv 192.168.0.124 2377` from the Pi
2. If port 2377 is reachable, get the swarm join token (`docker swarm join-token worker`) and attempt `docker swarm join` from the Pi
3. Watch for the Pi also needing ports 7946 (TCP/UDP) and 4789 (UDP) — these are required for full overlay network functionality after joining
4. If `pf` proves too fragile (VM IP changes on restart), consider running a native Linux swarm manager instead — `setup.sh` already targets Linux (`yq_linux_amd64`)
