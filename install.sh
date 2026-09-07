#!/usr/bin/env bash
# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║  ███╗   ██╗ ██████╗ ██████╗ ██████╗  █████╗ ████████╗                   ║
# ║  ████╗  ██║██╔═══██╗██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝                   ║
# ║  ██╔██╗ ██║██║   ██║██████╔╝███████║███████║   ██║                      ║
# ║  ██║╚██╗██║██║   ██║██╔══██╗██╔══██║██╔══██║   ██║                      ║
# ║  ██║ ╚████║╚██████╔╝██║  ██║██║  ██║██║  ██║   ██║                      ║
# ║  ╚═╝  ╚═══╝ ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝                      ║
# ╠═══════════════════════════════════════════════════════════════════════════╣
# ║  🛡️  تونل امن GRE-over-IPsec برای لینوکس                            ║
# ║  📺 YouTube: https://youtube.com/@PDNC30                                ║
# ║  📢 Telegram: https://t.me/PDNCzone                                    ║
# ║  💬 Support:  https://t.me/dncdirect                                   ║
# ╚═══════════════════════════════════════════════════════════════════════════╝
set -euo pipefail

# ── Colors ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ── Logo ───────────────────────────────────────────────────────────────────
print_logo() {
    clear 2>/dev/null || printf "\033c" 2>/dev/null || echo
    echo -e "${CYAN}"
    cat << 'EOF'
    ███╗   ██╗ ██████╗ ██████╗ ██████╗  █████╗ ████████╗
    ████╗  ██║██╔═══██╗██╔══██╗██╔══██╗██╔══██╗╚══██╔══╝
    ██╔██╗ ██║██║   ██║██████╔╝███████║███████║   ██║   
    ██║╚██╗██║██║   ██║██╔══██╗██╔══██║██╔══██║   ██║   
    ██║ ╚████║╚██████╔╝██║  ██║██║  ██║██║  ██║   ██║   
    ╚═╝  ╚═══╝ ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝   
╔═══════════════════════════════════════════════════════════════════════════╗
║  🛡️  GRE-over-IPsec Tunnel Manager — Professional Edition               ║
╚═══════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo -e "  ${GREEN}📺 YouTube:${NC}    https://youtube.com/@PDNC30"
    echo -e "  ${GREEN}📢 Telegram:${NC}   https://t.me/PDNCzone"
    echo -e "  ${GREEN}💬 Support:${NC}    https://t.me/dncdirect"
    echo -e "  ${GREEN}🐙 GitHub:${NC}     https://github.com/pdnczone/nosrat"
    echo ""
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# ── Helpers ────────────────────────────────────────────────────────────────
log()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
die()  { echo -e "${RED}[✗]${NC} $*\n" >&2; exit 1; }

# ── Check root ─────────────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || die "لطفاً با sudo اجرا کنید / Run as root (sudo ./install.sh)"

print_logo

# ── Interactive wizard ────────────────────────────────────────────────────
echo -e "${BOLD}🚀 Interactive Setup Wizard / جادویر نصب اینتراکتیو${NC}"
echo ""
echo -e "  ${CYAN}Language / زبان:${NC}"
echo "    1) English"
echo "    2) فارسی"
echo ""
read -p "Choose / انتخاب کنید [1-2]: " lang
lang=${lang:-1}

if [[ "$lang" == "2" ]]; then
    MSG_WELCOME="به نصب‌کننده nosrat خوش آمدید!"
    MSG_DEPS="در حال نصب وابستگی‌ها..."
    MSG_BUILD="در حال ساختن باینری..."
    MSG_CONFIG="در حال آماده‌سازی تنظیمات..."
    MSG_FIREWALL="در حال پیکربندی فایروال..."
    MSG_DONE="نصب با موفقیت انجام شد!"
    MSG_CHECK_CONFIG="لطفاً فایل تنظیمات را ویرایش کنید:"
    MSG_START_CMD="سپس دستور زیر را اجرا کنید:"
else
    MSG_WELCOME="Welcome to the nosrat installer!"
    MSG_DEPS="Installing dependencies..."
    MSG_BUILD="Building binary..."
    MSG_CONFIG="Preparing configuration..."
    MSG_FIREWALL="Configuring firewall..."
    MSG_DONE="Installation complete!"
    MSG_CHECK_CONFIG="Please edit the configuration file:"
    MSG_START_CMD="Then run:"
fi

echo ""
echo -e "${BOLD}$MSG_WELCOME${NC}"
echo ""

# ── Step 1: Dependencies ──────────────────────────────────────────────────
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}Step 1/6 — Dependencies / وابستگی‌ها${NC}"
echo ""

if command -v apt-get &>/dev/null; then
    log "$MSG_DEPS"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y --no-install-recommends \
        golang-go iproute2 nftables strongswan strongswan-swanctl \
        iputils-ping conntrack jq 2>&1 | tail -3
    log "Dependencies installed ✅"
else
    warn "apt-get not found — please install Go, strongSwan, nftables manually"
fi

# ── Step 2: strongSwan ────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}Step 2/6 — strongSwan / تنظیمات IPsec${NC}"
echo ""

systemctl enable strongswan >/dev/null 2>&1 || true
mkdir -p /etc/swanctl/conf.d
log "strongSwan configured ✅"

# ── Step 3: Build binary ──────────────────────────────────────────────────
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}Step 3/6 — Build / ساخت باینری${NC}"
echo ""

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NOSRAT_BIN=/usr/local/bin/nosrat

if [[ -f "$SRC_DIR/cmd/nosrat/main.go" ]]; then
    log "$MSG_BUILD"
    ( cd "$SRC_DIR" && CGO_ENABLED=0 go build -o "$NOSRAT_BIN" ./cmd/nosrat )
    chmod 0755 "$NOSRAT_BIN"
    log "Binary installed: $NOSRAT_BIN ✅"
else
    warn "Source not found at $SRC_DIR/cmd/nosrat — skipping build"
fi

# ── Step 4: Config directory ──────────────────────────────────────────────
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}Step 4/6 — Configuration / پیکربندی${NC}"
echo ""

CONF_DIR=/etc/nosrat
mkdir -p "$CONF_DIR/secrets"
chmod 0700 "$CONF_DIR/secrets"
log "Config directory ready: $CONF_DIR ✅"

# ── Step 5: systemd ───────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}Step 5/6 — systemd Service / سرویس سیستم‌دای${NC}"
echo ""

SYSTEMD_UNIT=/etc/systemd/system/nosrat.service
if [[ -f "$SRC_DIR/systemd/nosrat.service" ]]; then
    install -m 0644 "$SRC_DIR/systemd/nosrat.service" "$SYSTEMD_UNIT"
    systemctl daemon-reload
    systemctl enable nosrat.service >/dev/null
    log "systemd service installed ✅"
else
    warn "systemd unit not found — skipping"
fi

# ── Step 6: Firewall ──────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}Step 6/6 — Firewall / فایروال${NC}"
echo ""

systemctl enable nftables >/dev/null 2>&1 || true
systemctl start nftables 2>/dev/null || true
log "nftables ready (will be configured by 'nosrat start') ✅"

# ── Summary ───────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                        🎉 $MSG_DONE 🎉                         ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  $MSG_CHECK_CONFIG"
echo -e "    ${CYAN}$CONF_DIR/tunnel.yaml${NC}"
echo ""
echo -e "  $MSG_START_CMD"
echo -e "    ${CYAN}systemctl start nosrat${NC}"
echo -e "    ${CYAN}nosrat status${NC}"
echo -e "    ${CYAN}nosrat diagnose${NC}"
echo ""
echo -e "  ${YELLOW}📺 YouTube:${NC}    https://youtube.com/@PDNC30"
echo -e "  ${YELLOW}📢 Telegram:${NC}   https://t.me/PDNCzone"
echo -e "  ${YELLOW}💬 Support:${NC}    https://t.me/dncdirect"
echo -e "  ${YELLOW}🐙 GitHub:${NC}     https://github.com/pdnczone/nosrat"
echo ""
echo -e "  ${BOLD}Quick install command / دستور نصب سریع:${NC}"
echo -e "    ${CYAN}curl -sL https://raw.githubusercontent.com/pdnczone/nosrat/main/install.sh | sudo bash${NC}"
echo ""
