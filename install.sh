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

# ── Download nosrat binary from GitHub ───────────────────────────────────
log "Downloading nosrat binary from GitHub..."
ARCH="$(uname -m)"
case "$ARCH" in
    x86_64)  GOARCH="amd64" ;;
    aarch64) GOARCH="arm64" ;;
    armv7l)  GOARCH="armv7" ;;
    *)
        die "Unsupported architecture: $ARCH (supported: amd64, arm64, armv7)"
        ;;
esac

# Download the latest release from GitHub
DOWNLOAD_URL="https://github.com/pdnczone/nosrat/releases/latest/download/nosrat-linux-${GOARCH}"
TMP_BIN="$(mktemp /tmp/nosrat.XXXXXX)"

if ! curl -fsSL -o "$TMP_BIN" "$DOWNLOAD_URL" 2>/dev/null; then
    # Fallback: if no release binary exists yet, try to build from source
    warn "Pre-built binary not available for ${GOARCH}, building from source..."
    
    if ! command -v go &>/dev/null; then
        apt-get install -y --no-install-recommends golang-go 2>&1 | tail -2 || \
            die "Go is required to build from source. Install golang-go manually."
    fi
    
    # Clone to a temp directory to avoid issues with piped script
    TMP_SRC="$(mktemp -d /tmp/nosrat-src.XXXXXX)"
    log "Cloning repository..."
    if ! git clone --depth 1 https://github.com/pdnczone/nosrat.git "$TMP_SRC" 2>&1 | tail -3; then
        die "Failed to clone repository"
    fi
    
    log "Building nosrat binary..."
    ( cd "$TMP_SRC" && CGO_ENABLED=0 go build -o "$TMP_BIN" ./cmd/nosrat/main.go 2>&1 ) || \
        die "Build failed"
    
    rm -rf "$TMP_SRC"
fi

install -m 0755 "$TMP_BIN" /usr/local/bin/nosrat
rm -f "$TMP_BIN"
log "Binary installed at /usr/local/bin/nosrat"

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
