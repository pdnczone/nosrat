#!/usr/bin/env bash
# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║  ███╗   ██╗ ██████╗ ██████╗ ██████╗  █████╗ ████████╗                   ║
# ║  ████╗  ██║██╔═══██╗██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝                   ║
# ║  ██╔██╗ ██║██║   ██║██████╔╝███████║███████║   ██║                      ║
# ║  ██║╚██╗██║██║   ██║██╔══██╗██╔══██║██╔══██║   ██║                      ║
# ║  ██║ ╚████║╚██████╔╝██║  ██║██║  ██║██║  ██║   ██║                      ║
# ║  ╚═╝  ╚═══╝ ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝                      ║
# ╠═══════════════════════════════════════════════════════════════════════════╣
# ║  🛡️  GRE-over-IPsec Tunnel Manager — nosrat                            ║
# ║  📺 YouTube: https://youtube.com/@PDNC30                                ║
# ║  📢 Telegram: https://t.me/PDNCzone                                    ║
# ║  💬 Support:  https://t.me/dncdirect                                   ║
# ╚═══════════════════════════════════════════════════════════════════════════╝
#
# Safe to re-run: every step checks current state before changing anything.
set -Eeuo pipefail

# ── Colors ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ── Helpers ────────────────────────────────────────────────────────────────
log()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
die()  { echo -e "${RED}[✗]${NC} $*\n" >&2; exit 1; }

cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        echo ""
        echo -e "${RED}Installation failed (exit $exit_code)${NC}"
        echo -e "${YELLOW}For help: https://t.me/dncdirect${NC}"
    fi
}
trap cleanup EXIT

# ── Root check ───────────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || die "Run as root (sudo ./install.sh)"

# ── Header ────────────────────────────────────────────────────────────────
clear 2>/dev/null || printf "\033c" 2>/dev/null || true
echo -e "${CYAN}"
cat << 'EOF'
    ███╗   ██╗ ██████╗ ██████╗ ██████╗  █████╗ ████████╗
    ████╗  ██║██╔═══██╗██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝
    ██╔██╗ ██║██║   ██║██████╔╝███████║███████║   ██║
    ██║╚██╗██║██║   ██║██╔══██╗██╔══██║██╔══██║   ██║
    ██║ ╚████║╚██████╔╝██║  ██║██║  ██║██║  ██║   ██║
    ╚═╝  ╚═══╝ ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝

  🛡️  GRE-over-IPsec Tunnel Manager — nosrat
EOF
echo -e "${NC}"
echo -e "  ${GREEN}📺 YouTube:${NC}    https://youtube.com/@PDNC30"
echo -e "  ${GREEN}📢 Telegram:${NC}   https://t.me/PDNCzone"
echo -e "  ${GREEN}💬 Support:${NC}    https://t.me/dncdirect"
echo ""

# ── Installation ───────────────────────────────────────────────────────────
log "Installing dependencies..."
export DEBIAN_FRONTEND=noninteractive
if command -v apt-get &>/dev/null; then
    apt-get update -qq
    apt-get install -y --no-install-recommends \
        golang-go iproute2 nftables strongswan strongswan-swanctl \
        iputils-ping conntrack jq 2>&1 | tail -3
elif command -v dnf &>/dev/null; then
    dnf install -y golang iproute nftables strongswan strongswan-charon \
        iputils conntrack-tools jq 2>&1 | tail -3
fi
log "Dependencies installed"

# ── Build ──────────────────────────────────────────────────────────────────
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log "Building nosrat binary..."
( cd "$SRC_DIR" && CGO_ENABLED=0 go build -o /usr/local/bin/nosrat ./cmd/nosrat )
chmod 0755 /usr/local/bin/nosrat
log "Binary installed at /usr/local/bin/nosrat"

# ── Prepare config directory ──────────────────────────────────────────────
log "Preparing configuration..."
mkdir -p /etc/nosrat/secrets
chmod 0700 /etc/nosrat/secrets

# ── Install systemd service ───────────────────────────────────────────────
log "Installing systemd service..."
if [[ -f "$SRC_DIR/systemd/nosrat.service" ]]; then
    install -m 0644 "$SRC_DIR/systemd/nosrat.service" /etc/systemd/system/nosrat.service
    systemctl daemon-reload
    log "systemd service installed"
else
    warn "systemd unit not found - skipping"
fi

# ── Enable nftables ───────────────────────────────────────────────────────
systemctl enable nftables >/dev/null 2>&1 || true

# ── Done ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║               Installation Complete! 🎉                                ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Run the interactive manager:${NC}"
echo -e "    ${CYAN}nosrat${NC}"
echo ""
echo -e "  ${YELLOW}📺 YouTube:${NC}    https://youtube.com/@PDNC30"
echo -e "  ${YELLOW}📢 Telegram:${NC}   https://t.me/PDNCzone"
echo -e "  ${YELLOW}💬 Support:${NC}    https://t.me/dncdirect"
echo ""
