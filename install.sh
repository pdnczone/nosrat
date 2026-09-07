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

# ── Install nosrat: interactive menu + non-interactive CLI + dispatcher ──
# Layout:
#   /usr/local/bin/nosrat-menu  → interactive bash menu (human terminal use)
#   /usr/local/bin/nosrat-cli   → non-interactive Go CLI (panel / scripts / cron)
#   /usr/local/bin/nosrat       → dispatcher: no args = menu, subcommand = CLI
log "Installing nosrat (menu + CLI + dispatcher)..."

# 1) Interactive menu script
TMP_SCRIPT="$(mktemp /tmp/nosrat-menu.XXXXXX)"
DOWNLOAD_URL="https://raw.githubusercontent.com/pdnczone/nosrat/main/cmd/nosrat/nosrat.sh"
if curl -fsSL -o "$TMP_SCRIPT" "$DOWNLOAD_URL" 2>/dev/null; then
    :
elif [[ -f "./cmd/nosrat/nosrat.sh" ]]; then
    warn "Download failed, using local copy"
    cp "./cmd/nosrat/nosrat.sh" "$TMP_SCRIPT"
else
    die "Could not obtain nosrat.sh (download failed and no local clone)"
fi
chmod 0755 "$TMP_SCRIPT"
install -m 0755 "$TMP_SCRIPT" /usr/local/bin/nosrat-menu
rm -f "$TMP_SCRIPT"
log "interactive menu installed at /usr/local/bin/nosrat-menu"

# 2) Non-interactive Go CLI (used by Nosrat-Panel and scripts)
CLI_INSTALLED=0
# 2a) pre-built binary from GitHub Releases (preferred — no Go toolchain needed)
if command -v gh &>/dev/null; then
    ASSET_URL="$(gh api repos/pdnczone/nosrat/releases/latest \
        --jq '.assets[] | select(.name == "nosrat-linux-amd64") | .browser_download_url' 2>/dev/null)"
    if [[ -n "$ASSET_URL" ]]; then
        log "Downloading pre-built CLI from GitHub Releases..."
        if curl -fsSL -o /usr/local/bin/nosrat-cli "$ASSET_URL" 2>/dev/null; then
            chmod 0755 /usr/local/bin/nosrat-cli
            CLI_INSTALLED=1
            log "CLI installed (release binary)"
        fi
    fi
fi
# 2b) build from source (local clone or Go toolchain)
if [[ $CLI_INSTALLED -eq 0 ]] && command -v go &>/dev/null; then
    SRC_DIR="./"
    [[ ! -f "./cmd/nosrat/main.go" ]] && SRC_DIR="/root/nosrat"
    if [[ -f "$SRC_DIR/cmd/nosrat/main.go" ]]; then
        log "Building CLI from source (go build)..."
        if (cd "$SRC_DIR" && CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /usr/local/bin/nosrat-cli ./cmd/nosrat) 2>/dev/null; then
            CLI_INSTALLED=1
            log "CLI installed (built from source)"
        fi
    fi
fi
# 2c) last resort: build toolchain not present — fetch go toolchain-free fallback
if [[ $CLI_INSTALLED -eq 0 ]]; then
    if apt-get install -y -qq golang-go &>/dev/null && [[ -f "./cmd/nosrat/main.go" ]]; then
        (cd "./" && CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /usr/local/bin/nosrat-cli ./cmd/nosrat) 2>/dev/null \
            && CLI_INSTALLED=1
    fi
fi
if [[ $CLI_INSTALLED -eq 1 ]]; then
    chmod 0755 /usr/local/bin/nosrat-cli
else
    warn "Could not build/download the Go CLI — 'nosrat <command>' will be unavailable (menu only). Install golang and re-run, or publish a release binary."
fi

# 3) Dispatcher
cat > /usr/local/bin/nosrat << 'DISPATCHER'
#!/usr/bin/env bash
# nosrat dispatcher — non-interactive subcommands go to the Go CLI,
# no-args falls back to the interactive menu.
#
#   nosrat            → interactive menu (terminal use)
#   nosrat start      → Go CLI (panel / scripts / cron)
#   nosrat status     → Go CLI
#   ...
set -euo pipefail

MENU=/usr/local/bin/nosrat-menu
CLI=/usr/local/bin/nosrat-cli

# No argument → interactive menu (preserve existing UX for humans)
if [[ $# -eq 0 ]]; then
  if [[ -x "$MENU" ]]; then
    exec "$MENU"
  fi
  exec "$CLI"
fi

# Any subcommand → delegate to the non-interactive Go CLI
if [[ -x "$CLI" ]]; then
  exec "$CLI" "$@"
fi

# CLI missing → warn and fall back to menu so the user still gets something
echo "[nosrat] $CLI not found; falling back to interactive menu." >&2
if [[ -x "$MENU" ]]; then
  exec "$MENU" "$@"
fi
exec "$CLI" "$@"
DISPATCHER
chmod 0755 /usr/local/bin/nosrat
log "dispatcher installed at /usr/local/bin/nosrat"

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
