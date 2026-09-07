# nosrat — GRE-over-IPsec Tunnel Manager

A production-oriented tunnel manager for Ubuntu 24.04 LTS: builds a kernel
GRE tunnel between two servers and protects it end-to-end with strongSwan
(IKEv2 + ESP, IPsec **Transport Mode**). Ships as a single static Go binary
(`nosrat`) plus a systemd service - no Docker, no external Go modules.

```
Internet
   │
   ▼
Server A ── GRE encapsulate ── IPsec (ESP, transport mode) ── Internet ──▶
                                                                 IPsec decrypt
                                                                     │
                                                                  GRE decap
                                                                     │
                                                                     ▼
                                                                  Server B
```

## 1. Architecture decisions

| Question | Decision | Why |
|---|---|---|
| Transport vs Tunnel mode | **Transport** | GRE already provides the encapsulation between the two fixed public IPs. IPsec Tunnel Mode would add a *second* outer IP header for no benefit, wasting ~20 bytes of MTU per packet. Transport mode protects exactly the GRE packets between the two known endpoints. |
| strongSwan vs raw XFRM vs custom IPsec | **strongSwan + Linux XFRM** | strongSwan is a mature, audited IKEv2 implementation; it negotiates keys and installs them straight into the kernel's XFRM stack (fast, AES-NI-aware). Writing a custom IKE/ESP stack is high-risk and provides zero benefit here. |
| Config format | Custom minimal YAML | Avoids pulling in an external Go module (`gopkg.in/yaml.v3`) purely for config parsing, keeping `go build` fully offline-capable on a fresh VPS. |
| Secrets | PSK in `/etc/nosrat/secrets/psk`, mode `0600`, never in YAML | Config files get copied around, committed to git-by-accident, attached to tickets. Secret material lives in one file with enforced permissions, checked at load time. |
| GRE key/routing | Kernel `ip tunnel` + `ip route`, no userspace forwarding | Kernel networking is faster and simpler to reason about than a userspace tunnel daemon. |
| Firewall | Dedicated `inet nosrat` nftables table | Never touches the operator's existing firewall rules; fully removable with `nosrat uninstall`. |

## 2. MTU / MSS (exact budget)

```
Ethernet/link MTU                         1500
  - Outer IPv4 header                      -20
  - ESP header (SPI+SeqNo) + IV (GCM)       -16
  - ESP trailer (pad+len+next) + ICV-16     -18
  - GRE header (no key/seq/csum)             -4
                                          ------
Usable tunnel MTU                         1442   → config default 1400 (safety margin)
TCP MSS to clamp to                       1360   (on MTU 1400)
```
Run `scripts/mtu-calc.sh <link_mtu>` to recompute for a non-standard uplink
(e.g. a VPS behind an 1450-MTU overlay). `nosrat` applies MSS clamping
automatically via nftables (`mtu.mss_clamp: true`), so PMTUD black-holing
(common across ESP boundaries where ICMP is filtered) mostly doesn't matter.

## 3. Threat model

**In scope / defended against:**
- Passive eavesdropping on the public link → AES-256-GCM confidentiality.
- Tampering / packet injection → GCM integrity + XFRM anti-replay window.
- Replay attacks → kernel XFRM replay window (enabled by default under IKEv2/ESP).
- Credential exposure via config files → PSK isolated to a `0600` root-only file, validated at load time; `nosrat` refuses to start if permissions are wrong.
- Casual network scanning → no listening ports beyond UDP 500/4500 (IKE); ESP/GRE are not "ports" and don't respond to probes the way a service would.
- Weak crypto downgrade → `nosrat` **rejects** DH groups < 14 (MODP2048) and non-AEAD/non-AES-256 ciphers at config-load time, before anything is negotiated.

**Explicitly out of scope (needs separate controls):**
- Compromise of either host's OS (root on either box = game over; this is inherent to any tunnel).
- DDoS volumetric attacks against UDP 500 (use upstream rate-limiting / a DDoS-protected uplink, not this tool).
- Traffic analysis (packet timing/size can still leak metadata even when encrypted).

## 4. Firewall requirements

| Protocol/Port | When needed |
|---|---|
| UDP 500 | Always — initial IKE_SA negotiation |
| UDP 4500 | Always — IKE NAT-T detection, and becomes the ESP transport too if NAT is detected between the peers |
| ESP (IP proto 50) | Needed when there is **no NAT** between the two servers (typical VPS-to-VPS with public IPs on both ends) |
| GRE (IP proto 47) | Always — this carries the actual tunneled payload, itself protected by ESP |

If NAT-T activates (one side behind NAT), strongSwan automatically
re-encapsulates ESP inside UDP/4500; proto-50 traffic then isn't used and can
stay blocked with no functional impact.

## 5. Project layout

```
custom-gre-ipsec/
├── cmd/nosrat/            CLI entrypoint + starter config template
├── internal/config/       config load/validate + tiny YAML-subset parser
├── internal/gre/          kernel GRE interface lifecycle (via `ip`)
├── internal/ipsec/        swanctl config generation + strongSwan control
├── internal/routing/      sysctl (forward/rp_filter) + static routes
├── internal/firewall/     nftables `inet nosrat` table (ports + MSS clamp)
├── internal/health/       ICMP/SA/interface checks + auto-recovery
├── internal/diagnostics/  `nosrat diagnose` checklist
├── configs/               example tunnel.yaml
├── systemd/nosrat.service
├── scripts/               benchmark.sh, mtu-calc.sh
├── tests/test-plan.md
├── install.sh / uninstall.sh
└── go.mod
```

## 6. CLI reference

```
nosrat init        # create /etc/nosrat, generate PSK, write starter config
nosrat create      # (re)build GRE iface + strongSwan connection from config
nosrat start       # bring tunnel up: GRE + IPsec SA + routes + firewall
nosrat stop        # tear down IPsec SA, GRE down (config stays on disk)
nosrat restart
nosrat status      # human-readable summary (see below)
nosrat health       # one health-check pass
nosrat routes      # routes installed on the GRE interface
nosrat ipsec       # raw `swanctl --list-sas` detail
nosrat logs        # journalctl for nosrat + strongswan
nosrat diagnose    # full checklist with fix commands
nosrat uninstall   # remove GRE/IPsec/firewall (keeps /etc/nosrat config)
```

Example `nosrat status` output:
```
GRE Tunnel
----------------------------
Name:       nosrat
Status:     UP
Local:      10.200.0.1
Remote:     10.200.0.2
MTU:        1400

IPsec
----------------------------
IKE:        ESTABLISHED
ESP:        INSTALLED
Encryption: AES_256_GCM_16
PFS:        MODP_2048

Health
----------------------------
Latency:    42 ms
Packet Loss: 0%
```

## 7. Deploy from scratch on two VPS

Only substitute the IPs below — everything else is copy/paste identical on
both servers except where marked **A-only** / **B-only**.

Assume:
- Server A public IP: `A_PUBLIC_IP`
- Server B public IP: `B_PUBLIC_IP`
- GRE inner network: `10.200.0.1/30` (A) ↔ `10.200.0.2/30` (B)

### Step 1 — get the code onto both servers
```bash
# on both A and B
git clone <this-repo-url> custom-gre-ipsec   # or scp the folder over
cd custom-gre-ipsec
```

### Step 2 — install (both servers)
```bash
sudo ./install.sh
```
This installs Go/strongSwan/nftables/iproute2, builds `nosrat`, generates a
**per-server** PSK at `/etc/nosrat/secrets/psk`, and writes a starter config
at `/etc/nosrat/tunnel.yaml`.

> ⚠️ The PSK must be **identical on both servers** (it's a pre-shared key).
> After running install.sh on Server A, copy its generated PSK to Server B:
> ```bash
> # on A
> cat /etc/nosrat/secrets/psk
> # on B — replace the auto-generated one with A's value
> echo '<the-psk-from-A>' | sudo tee /etc/nosrat/secrets/psk
> sudo chmod 600 /etc/nosrat/secrets/psk
> ```

### Step 3 — edit the config

**On Server A** (`/etc/nosrat/tunnel.yaml`):
```yaml
local:
  public_ip: "A_PUBLIC_IP"
  gre_ip: "10.200.0.1/30"
remote:
  public_ip: "B_PUBLIC_IP"
  gre_ip: "10.200.0.2/30"
```

**On Server B** (`/etc/nosrat/tunnel.yaml`) — endpoints swapped:
```yaml
local:
  public_ip: "B_PUBLIC_IP"
  gre_ip: "10.200.0.2/30"
remote:
  public_ip: "A_PUBLIC_IP"
  gre_ip: "10.200.0.1/30"
```

If you want to route a whole LAN behind each server through the tunnel, add
on both sides (adjust CIDRs to your actual LANs):
```yaml
routing:
  enabled: true
  static_routes:
    - to: 10.10.0.0/24   # the *other* server's LAN
      via_gre: true
```

### Step 4 — bring the tunnel up (both servers)
```bash
sudo nosrat create
sudo systemctl start nosrat
nosrat status
```

### Step 5 — verify
```bash
# on A
ping -c 5 10.200.0.2
nosrat diagnose
```
All checks should show `[✓]`. If something shows `[✗]`, the `diagnose`
output includes the exact fix command.

### Step 6 (optional) — benchmark
```bash
# on B
iperf3 -s &
# on A
./scripts/benchmark.sh B_PUBLIC_IP 10.200.0.2
```

### Removing it later
```bash
sudo ./uninstall.sh          # keeps /etc/nosrat config + PSK
sudo ./uninstall.sh --purge  # also wipes config + PSK
```

## 8. What "production-ready" means here — and its limits

This project gives you a real, working control plane over standard Linux
primitives (kernel GRE, XFRM via strongSwan, nftables, systemd) rather than a
one-off shell script. Before trusting it with real traffic, still run the
full [test plan](tests/test-plan.md) against your actual two VPS — packet
loss/latency injection, reboot, and NAT-T behavior all depend on your
specific cloud provider's network, and no amount of code review substitutes
for testing on the real path.
