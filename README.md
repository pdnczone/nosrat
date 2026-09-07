# 🛡️ nosrat — GRE-over-IPsec Tunnel Manager

<div align="center">

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Go Report Card](https://goreportcard.com/badge/github.com/pdnczone/nosrat)](https://goreportcard.com/report/github.com/pdnczone/nosrat)
[![Ubuntu 24.04](https://img.shields.io/badge/Ubuntu-24.04-orange.svg)](https://ubuntu.com/)
[![strongSwan](https://img.shields.io/badge/strongSwan-IKEv2-green.svg)](https://www.strongswan.org/)

📺 **[YouTube: @PDNC30](https://youtube.com/@PDNC30)** | 📢 **[Telegram: @PDNCzone](https://t.me/PDNCzone)** | 💬 **[Support](https://t.me/dncdirect)**

</div>

---

A production-oriented tunnel manager for Ubuntu 24.04 LTS: builds a kernel GRE tunnel between two servers and protects it end-to-end with strongSwan (IKEv2 + ESP, IPsec **Transport Mode**). Ships as a single static Go binary (`nosrat`) plus a systemd service — no Docker, no external Go modules.

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

### ⚡ Quick Install

```bash
# One-line installer (interactive)
curl -sL https://raw.githubusercontent.com/pdnczone/nosrat/main/install.sh | sudo bash

# Or manual install
git clone https://github.com/pdnczone/nosrat.git
cd nosrat
sudo ./install.sh
```

### 🏗️ Architecture

| Component | Technology | Why |
|-----------|-----------|-----|
| **IPsec** | strongSwan + Linux XFRM | Mature, audited IKEv2 implementation |
| **Tunnel** | Kernel GRE via `ip tunnel` | Faster than userspace forwarding |
| **Crypto** | AES-256-GCM, MODP_2048 PFS | No weak cipher downgrade allowed |
| **Firewall** | nftables `inet nosrat` table | Isolated from existing rules |
| **Service** | systemd with auto-recovery | Production-grade process management |

### 📊 MTU Budget

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

### 🔒 Threat Model

**Defended against:**
- ✅ Passive eavesdropping → AES-256-GCM confidentiality
- ✅ Tampering / injection → GCM integrity + XFRM anti-replay
- ✅ Replay attacks → kernel XFRM replay window
- ✅ Credential exposure → PSK isolated to `0600` root-only file
- ✅ Weak crypto downgrade → rejects DH < 14, non-AEAD/non-AES-256

**Out of scope:**
- ❌ Host OS compromise (root = game over)
- ❌ Volumetric DDoS against UDP 500
- ❌ Traffic analysis (timing/size metadata)

### 🚀 Deploy in 5 Steps

```bash
# 1. Clone & install on BOTH servers
git clone https://github.com/pdnczone/nosrat.git
cd nosrat && sudo ./install.sh

# 2. Copy PSK from Server A to Server B
# On A: cat /etc/nosrat/secrets/psk
# On B: echo '<psk-from-A>' | sudo tee /etc/nosrat/secrets/psk

# 3. Edit config on each server
sudo nano /etc/nosrat/tunnel.yaml

# 4. Start tunnel (both servers)
sudo systemctl start nosrat

# 5. Verify
nosrat status
nosrat diagnose
```

### 📋 CLI Reference

```bash
nosrat init          # create /etc/nosrat, generate PSK, write starter config
nosrat create        # (re)build GRE iface + strongSwan connection
nosrat start         # bring tunnel up: GRE + IPsec SA + routes + firewall
nosrat stop          # tear down IPsec SA, GRE down
nosrat restart       # restart tunnel
nosrat status        # human-readable summary
nosrat health        # one health-check pass
nosrat routes        # routes installed on the GRE interface
nosrat ipsec         # raw `swanctl --list-sas` detail
nosrat logs          # journalctl for nosrat + strongswan
nosrat diagnose      # full checklist with fix commands
nosrat uninstall     # remove GRE/IPsec/firewall (keeps config)
```

### 📁 Project Layout

```
nosrat/
├── cmd/nosrat/            # CLI entrypoint + starter config template
├── internal/config/       # config load/validate + tiny YAML-subset parser
├── internal/gre/          # kernel GRE interface lifecycle (via `ip`)
├── internal/ipsec/        # swanctl config generation + strongSwan control
├── internal/routing/      # sysctl (forward/rp_filter) + static routes
├── internal/firewall/     # nftables `inet nosrat` table (ports + MSS clamp)
├── internal/health/       # ICMP/SA/interface checks + auto-recovery
├── internal/diagnostics/  # `nosrat diagnose` checklist
├── configs/               # example tunnel.yaml
├── systemd/nosrat.service
├── scripts/               # benchmark.sh, mtu-calc.sh
├── tests/test-plan.md
├── install.sh / uninstall.sh
└── go.mod
```

### 🔥 Firewall Requirements

| Protocol/Port | When needed |
|---|---|
| UDP 500 | Always — initial IKE_SA negotiation |
| UDP 4500 | Always — IKE NAT-T detection |
| ESP (IP proto 50) | When **no NAT** between servers |
| GRE (IP proto 47) | Always — carries tunneled payload |

---

## 📜 License

MIT License — see [LICENSE](./LICENSE) for details.

---

<div align="center">

**[📺 YouTube](https://youtube.com/@PDNC30)** | **[📢 Telegram](https://t.me/PDNCzone)** | **[💬 Support](https://t.me/dncdirect)** | **[🐙 GitHub](https://github.com/pdnczone/nosrat)**

Made with ❤️ by **PDNC Team**

</div>
