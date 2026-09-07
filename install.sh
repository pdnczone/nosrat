#!/usr/bin/env bash
# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║                                                                           ║
# ║   ███╗   ██╗  ██████╗ ███████╗ ██████╗  █████╗ ████████╗                  ║
# ║   ████╗  ██║██╔═══██╗██╔════╝██╔═══██╗██╔══██╗╚══██╔══╝                  ║
# ║   ██╔██╗ ██║██║   ██║███████╗██║   ██║███████║   ██║                     ║
# ║   ██║╚██╗██║██║   ██║╚════██║██║   ██║██╔══██║   ██║                     ║
# ║   ██║ ╚████║╚██████╔╝███████║╚██████╔╝██║  ██║   ██║                     ║
# ║   ╚═╝  ╚═══╝ ╚═════╝ ╚══════╝ ╚═════╝ ╚═╝  ╚═╝   ╚═╝                     ║
# ║                                                                           ║
# ║   🛡️  GRE-over-IPsec Tunnel Manager — nosrat                             ║
# ║   📺 YouTube:    https://youtube.com/@PDNC30                              ║
# ║   📢 Telegram:   https://t.me/PDNCzone                                   ║
# ║   💬 Support:    https://t.me/dncdirect                                  ║
# ║                                                                           ║
# ╚═══════════════════════════════════════════════════════════════════════════╝
#
# Safe to re-run: every step checks current state before changing anything.
set -Eeo pipefail

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

 ███╗   ██╗  ██████╗ ███████╗ ██████╗  █████╗ ████████╗
 ████╗  ██║██╔═══██╗██╔════╝██╔═══██╗██╔══██╗╚══██╔══╝
 ██╔██╗ ██║██║   ██║███████╗██║   ██║███████║   ██║
 ██║╚██╗██║██║   ██║╚════██║██║   ██║██╔══██║   ██║
 ██║ ╚████║╚██████╔╝███████║╚██████╔╝██║  ██║   ██║
 ╚═╝  ╚═══╝ ╚═════╝ ╚══════╝ ╚═════╝ ╚═╝  ╚═╝   ╚═╝

EOF
echo -e "${NC}"
echo -e "  ${CYAN}🛡️  GRE-over-IPsec Tunnel Manager${NC}"
echo ""
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
        iproute2 nftables strongswan strongswan-swanctl \
        iputils-ping conntrack jq curl 2>&1 | tail -3
elif command -v dnf &>/dev/null; then
    dnf install -y iproute nftables strongswan strongswan-charon \
        iputils conntrack-tools jq curl 2>&1 | tail -3
fi
log "Dependencies installed"

# ── Download interactive nosrat script from GitHub ───────────────────────
log "Downloading nosrat interactive menu from GitHub..."
TMP_SCRIPT="$(mktemp /tmp/nosrat.XXXXXX)"
DOWNLOAD_URL="https://raw.githubusercontent.com/pdnczone/nosrat/main/cmd/nosrat/nosrat.sh"

if ! curl -fsSL -o "$TMP_SCRIPT" "$DOWNLOAD_URL" 2>/dev/null; then
    # Fallback: try to build from local source if we're running from a clone
    if [[ -f "./cmd/nosrat/nosrat.sh" ]]; then
        warn "Download failed, using local copy"
        cp "./cmd/nosrat/nosrat.sh" "$TMP_SCRIPT"
    else
        die "Could not download nosrat script from $DOWNLOAD_URL"
    fi
fi

chmod 0755 "$TMP_SCRIPT"
install -m 0755 "$TMP_SCRIPT" /usr/local/bin/nosrat
rm -f "$TMP_SCRIPT"
log "nosrat command installed at /usr/local/bin/nosrat"

# ── Prepare config directory ──────────────────────────────────────────────
log "Preparing configuration..."
mkdir -p /etc/nosrat/secrets
chmod 0700 /etc/nosrat/secrets

# ── Install systemd service ───────────────────────────────────────────────
log "Installing systemd service..."
TMP_SERVICE="$(mktemp /tmp/nosrat-service.XXXXXX)"
if curl -fsSL -o "$TMP_SERVICE" \
    "https://raw.githubusercontent.com/pdnczone/nosrat/main/systemd/nosrat.service" 2>/dev/null; then
    install -m 0644 "$TMP_SERVICE" /etc/systemd/system/nosrat.service
    rm -f "$TMP_SERVICE"
    systemctl daemon-reload
    log "systemd service installed"
else
    warn "Could not download systemd unit - skipping"
    rm -f "$TMP_SERVICE"
fi

# ── Enable nftables ───────────────────────────────────────────────────────
systemctl enable nftables >/dev/null 2>&1 || true

# ── Done ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              ✅  Installation Complete!                                  ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Run the interactive manager:${NC}"
echo -e "    ${CYAN}sudo nosrat${NC}"
echo ""
echo -e "  ${YELLOW}📺 YouTube:${NC}    https://youtube.com/@PDNC30"
echo -e "  ${YELLOW}📢 Telegram:${NC}   https://t.me/PDNCzone"
echo -e "  ${YELLOW}💬 Support:${NC}    https://t.me/dncdirect"
echo ""
