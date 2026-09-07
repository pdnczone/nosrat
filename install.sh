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

# ── Logo ───────────────────────────────────────────────────────────────────
print_logo() {
    clear 2>/dev/null || printf "\033c" 2>/dev/null || true
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

# ── Error handler ─────────────────────────────────────────────────────────
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        echo ""
        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${RED}Installation failed with exit code $exit_code${NC}"
        echo -e "${RED}Check the error message above for details.${NC}"
        echo -e "${YELLOW}If the problem persists, contact: https://t.me/dncdirect${NC}"
        echo ""
    fi
}
trap cleanup EXIT

# ── Check root ─────────────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || die "Run as root (sudo ./install.sh)"

# ── Detect installation mode ──────────────────────────────────────────────
INSTALL_MODE="local"
SRC_DIR=""

detect_mode() {
    # Check if we're being piped (curl | bash)
    if [[ -p /dev ]] || [[ ! -t 0 ]]; then
        INSTALL_MODE="remote"
        log "Remote installation mode detected (piped input)"
    else
        # Check if script file exists
        local script_path
        script_path="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
        if [[ -n "$script_path" && -f "$script_path/$(basename "${BASH_SOURCE[0]:-$0}")" ]]; then
            SRC_DIR="$script_path"
            INSTALL_MODE="local"
            log "Local installation mode detected"
        else
            INSTALL_MODE="remote"
            log "Remote installation mode detected"
        fi
    fi
}

# ── OS Detection ──────────────────────────────────────────────────────────
detect_os() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        OS_ID="${ID:-unknown}"
        OS_VERSION="${VERSION_ID:-unknown}"
        OS_NAME="${PRETTY_NAME:-unknown}"
    else
        OS_ID="unknown"
        OS_VERSION="unknown"
        OS_NAME="unknown"
    fi
    
    log "Detected OS: $OS_NAME"
    
    # Check if supported
    case "$OS_ID" in
        ubuntu)
            if [[ "${OS_VERSION%%.*}" -lt 22 ]]; then
                die "Ubuntu 22.04+ required (detected $OS_VERSION)"
            fi
            ;;
        debian)
            if [[ "${OS_VERSION%%.*}" -lt 12 ]]; then
                die "Debian 12+ required (detected $OS_VERSION)"
            fi
            ;;
        centos|rocky|alma)
            warn "RHEL-based OS detected. Package names may differ."
            ;;
        *)
            warn "Unsupported OS: $OS_ID. Proceeding anyway..."
            ;;
    esac
}

# ── Architecture Detection ────────────────────────────────────────────────
detect_arch() {
    ARCH="$(uname -m)"
    case "$ARCH" in
        x86_64|amd64)
            ARCH="amd64"
            GOARCH="amd64"
            ;;
        aarch64|arm64)
            ARCH="arm64"
            GOARCH="arm64"
            ;;
        armv7l|armhf)
            ARCH="arm"
            GOARCH="arm"
            ;;
        *)
            die "Unsupported architecture: $ARCH"
            ;;
    esac
    
    log "Detected architecture: $ARCH"
}

# ── Dependency Checks ─────────────────────────────────────────────────────
check_dependencies() {
    local missing=()
    
    # Check for required commands
    for cmd in ip systemctl; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        die "Missing required commands: ${missing[*]}"
    fi
    
    # Check systemd
    if ! pidof systemd &>/dev/null; then
        die "systemd is not running. nosrat requires systemd."
    fi
    
    log "All required dependencies present"
}

# ── Install packages ──────────────────────────────────────────────────────
install_packages() {
    log "Installing packages..."
    
    export DEBIAN_FRONTEND=noninteractive
    
    case "$OS_ID" in
        ubuntu|debian)
            apt-get update -qq
            apt-get install -y --no-install-recommends \
                golang-go iproute2 nftables strongswan strongswan-swanctl \
                iputils-ping conntrack jq 2>&1 | tail -5
            ;;
        centos|rocky|alma)
            dnf install -y \
                golang iproute nftables strongswan strongswan-charon \
                iputils conntrack-tools jq 2>&1 | tail -5
            ;;
        *)
            warn "Unknown OS — please install manually: Go, iproute2, nftables, strongSwan"
            ;;
    esac
    
    log "Packages installed"
}

# ── Build from source ─────────────────────────────────────────────────────
build_from_source() {
    local build_dir="$1"
    
    log "Building nosrat from source..."
    
    # Check Go version
    local go_version
    go_version="$(go version | grep -oE '[0-9]+\.[0-9]+' | head -1)"
    if [[ "${go_version%%.*}" -lt 1 ]] || [[ "${go_version%%.*}" -eq 1 && "${go_version##*.}" -lt 20 ]]; then
        die "Go 1.20+ required (detected $go_version)"
    fi
    
    # Build
    ( cd "$build_dir" && CGO_ENABLED=0 GOOS=linux GOARCH="$GOARCH" go build -o /usr/local/bin/nosrat ./cmd/nosrat ) || die "Build failed"
    chmod 0755 /usr/local/bin/nosrat
    
    log "Binary built and installed"
}

# ── Remote install (download release or build) ────────────────────────────
remote_install() {
    local temp_dir
    temp_dir="$(mktemp -d)"
    trap 'rm -rf "$temp_dir"' RETURN
    
    log "Downloading nosrat repository..."
    
    if command -v git &>/dev/null; then
        git clone --depth 1 https://github.com/pdnczone/nosrat.git "$temp_dir/nosrat" 2>&1 | tail -3
        build_from_source "$temp_dir/nosrat"
    else
        # Fallback: download tarball
        curl -fsSL "https://github.com/pdnczone/nosrat/archive/main.tar.gz" -o "$temp_dir/nosrat.tar.gz"
        tar xzf "$temp_dir/nosrat.tar.gz" -C "$temp_dir"
        build_from_source "$temp_dir/nosrat-main"
    fi
}

# ── Local install ─────────────────────────────────────────────────────────
local_install() {
    if [[ ! -d "$SRC_DIR" ]]; then
        die "Cannot determine source directory"
    fi
    
    build_from_source "$SRC_DIR"
}

# ── Configure strongSwan ─────────────────────────────────────────────────
configure_strongswan() {
    log "Configuring strongSwan..."
    
    systemctl enable strongswan >/dev/null 2>&1 || true
    
    mkdir -p /etc/swanctl/conf.d
    chmod 0750 /etc/swanctl/conf.d
    
    # Backup existing ipsec.conf if present
    if [[ -f /etc/ipsec.conf ]] && [[ ! -f /etc/ipsec.conf.nosrat-backup ]]; then
        cp /etc/ipsec.conf /etc/ipsec.conf.nosrat-backup
        log "Backed up /etc/ipsec.conf"
    fi
    
    log "strongSwan configured"
}

# ── Prepare config directory ──────────────────────────────────────────────
prepare_config() {
    log "Preparing configuration directory..."
    
    local conf_dir="/etc/nosrat"
    mkdir -p "$conf_dir/secrets"
    chmod 0700 "$conf_dir/secrets"
    
    # Generate starter config if not exists
    if [[ ! -f "$conf_dir/tunnel.yaml" ]]; then
        cat > "$conf_dir/tunnel.yaml" << 'EOF'
tunnel:
  name: nosrat

local:
  public_ip: ""
  gre_ip: "10.200.0.1/30"

remote:
  public_ip: ""
  gre_ip: "10.200.0.2/30"

ipsec:
  ike_version: 2
  mode: transport
  encryption: aes256gcm16
  integrity: ""
  dh_group: 14
  psk_file: /etc/nosrat/secrets/psk
  rekey_seconds: 3600
  dpd_delay: 10
  dpd_timeout: 30

routing:
  enabled: true
  static_routes: []

firewall:
  enabled: true
  allow_ssh: true

mtu:
  value: 1400
  mss_clamp: true

keepalive:
  enabled: true
  interval: 10

health:
  interval_seconds: 15
  latency_threshold_ms: 200
  loss_threshold_pct: 5
  auto_recover: true

failover:
  enabled: false
  secondary_public_ip: ""
  switch_after_failures: 3
EOF
        log "Starter config created: $conf_dir/tunnel.yaml"
    fi
    
    # Generate PSK if not exists
    if [[ ! -f "$conf_dir/secrets/psk" ]]; then
        local psk
        psk="$(openssl rand -hex 32 2>/dev/null || head -c 64 /dev/urandom | xxd -p | head -1)"
        echo -n "$psk" > "$conf_dir/secrets/psk"
        chmod 0600 "$conf_dir/secrets/psk"
        log "PSK generated: $conf_dir/secrets/psk"
    fi
    
    log "Configuration directory ready"
}

# ── Install systemd service ───────────────────────────────────────────────
install_systemd_service() {
    log "Installing systemd service..."
    
    local unit="/etc/systemd/system/nosrat.service"
    
    cat > "$unit" << 'EOF'
[Unit]
Description=nosrat (PDNC) GRE-over-IPsec tunnel manager (health/recovery daemon)
Documentation=https://github.com/pdnczone/nosrat
After=network-online.target strongswan.service
Wants=network-online.target
Requires=strongswan.service

[Service]
Type=simple
ExecStartPre=/usr/local/bin/nosrat start
ExecStart=/usr/local/bin/nosrat run-daemon
ExecStop=/usr/local/bin/nosrat stop
Restart=on-failure
RestartSec=5s
TimeoutStopSec=15s

# Security hardening
User=root
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/etc/nosrat /etc/swanctl/conf.d /etc/sysctl.d
PrivateTmp=true
ProtectKernelModules=false
ProtectKernelTunables=false

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=nosrat

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable nosrat.service >/dev/null
    
    log "systemd service installed"
}

# ── Configure firewall ────────────────────────────────────────────────────
configure_firewall() {
    log "Configuring firewall baseline..."
    
    systemctl enable nftables >/dev/null 2>&1 || true
    systemctl start nftables 2>/dev/null || true
    
    log "nftables ready (rules applied by 'nosrat start')"
}

# ── Main installation flow ────────────────────────────────────────────────
main() {
    print_logo
    detect_mode
    detect_os
    detect_arch
    check_dependencies
    install_packages
    
    case "$INSTALL_MODE" in
        remote)
            remote_install
            ;;
        local)
            local_install
            ;;
    esac
    
    configure_strongswan
    prepare_config
    install_systemd_service
    configure_firewall
    
    # Final summary
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    🎉 Installation Complete! 🎉                        ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${BOLD}Next steps:${NC}"
    echo ""
    echo -e "  1. Edit configuration:"
    echo -e "     ${CYAN}nano /etc/nosrat/tunnel.yaml${NC}"
    echo ""
    echo -e "  2. Copy PSK to remote server:"
    echo -e "     ${CYAN}cat /etc/nosrat/secrets/psk${NC}"
    echo ""
    echo -e "  3. Start tunnel:"
    echo -e "     ${CYAN}systemctl start nosrat${NC}"
    echo ""
    echo -e "  4. Check status:"
    echo -e "     ${CYAN}nosrat status${NC}"
    echo -e "     ${CYAN}nosrat diagnose${NC}"
    echo ""
    echo -e "  ${YELLOW}📺 YouTube:${NC}    https://youtube.com/@PDNC30"
    echo -e "  ${YELLOW}📢 Telegram:${NC}   https://t.me/PDNCzone"
    echo -e "  ${YELLOW}💬 Support:${NC}    https://t.me/dncdirect"
    echo ""
}

main "$@"
