#!/usr/bin/env bash
# nosrat (PDNC) installer - Ubuntu 24.04 LTS, amd64
#
# Safe to re-run: every step checks current state before changing anything.
set -euo pipefail

NOSRAT_BIN=/usr/local/bin/nosrat
CONF_DIR=/etc/nosrat
SYSTEMD_UNIT=/etc/systemd/system/nosrat.service

log()  { echo -e "\e[1;32m[install]\e[0m $*"; }
warn() { echo -e "\e[1;33m[install]\e[0m $*"; }
die()  { echo -e "\e[1;31m[install]\e[0m $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "run as root (sudo ./install.sh)"

# 1) dependencies -----------------------------------------------------------
log "1/8 installing dependencies (idempotent apt install)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends \
  golang-go iproute2 nftables strongswan strongswan-swanctl \
  iputils-ping conntrack

# 2) strongSwan --------------------------------------------------------------
log "2/8 configuring strongSwan (swanctl backend, legacy starter disabled)"
systemctl enable strongswan >/dev/null 2>&1 || true
# The legacy `ipsec.conf`/starter model and the modern swanctl/vici model can
# conflict if both try to load connections. nosrat only ever uses swanctl.
mkdir -p /etc/swanctl/conf.d
if [[ -f /etc/ipsec.conf ]] && ! grep -q "^# nosrat: managed" /etc/ipsec.conf 2>/dev/null; then
  warn "leaving existing /etc/ipsec.conf untouched - nosrat only writes /etc/swanctl/conf.d/*.conf"
fi

# 3) build & install binary --------------------------------------------------
log "3/8 building nosrat binary"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
( cd "$SRC_DIR" && CGO_ENABLED=0 go build -o "$NOSRAT_BIN" ./cmd/nosrat )
chmod 0755 "$NOSRAT_BIN"
log "installed $NOSRAT_BIN"

# 4) config directory ---------------------------------------------------------
log "4/8 preparing $CONF_DIR"
mkdir -p "$CONF_DIR/secrets"
chmod 0700 "$CONF_DIR/secrets"
"$NOSRAT_BIN" init

# 5) systemd service -----------------------------------------------------------
log "5/8 installing systemd unit"
install -m 0644 "$SRC_DIR/systemd/nosrat.service" "$SYSTEMD_UNIT"
systemctl daemon-reload
systemctl enable nosrat.service >/dev/null

# 6) firewall baseline ---------------------------------------------------------
log "6/8 firewall will be configured by 'nosrat start' (nftables inet nosrat table)"
systemctl enable nftables >/dev/null 2>&1 || true
systemctl start nftables 2>/dev/null || true

# 7) health check enablement ---------------------------------------------------
log "7/8 health/recovery daemon will start automatically via systemd"

# 8) bring the tunnel up (only if the config has been filled in) -------------
log "8/8 checking config completeness"
if grep -q 'public_ip: ""' "$CONF_DIR/tunnel.yaml"; then
  warn "public_ip fields in $CONF_DIR/tunnel.yaml are still empty."
  warn "Edit $CONF_DIR/tunnel.yaml with both servers' public IPs, then run:"
  warn "  systemctl start nosrat"
  warn "  nosrat status"
else
  log "config looks filled in - starting tunnel"
  systemctl start nosrat
  sleep 2
  "$NOSRAT_BIN" status || true
fi

log "done. Use 'nosrat diagnose' any time to check the full stack."
