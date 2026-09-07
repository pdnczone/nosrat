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
set -euo pipefail

# ── Colors ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ── Paths ─────────────────────────────────────────────────────────────────
NOSRAT_BIN="/usr/local/bin/nosrat"
CONF_DIR="/etc/nosrat"
PSK_FILE="$CONF_DIR/secrets/psk"
CONF_FILE="$CONF_DIR/tunnel.yaml"

# ── Helpers ────────────────────────────────────────────────────────────────
log()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*" >&2; }
ok()   { echo -e "${GREEN}[✓]${NC} $*"; }
die()  { err "$*"; return 1; }

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
EOF
    echo -e "${NC}"
}

# ── Main Menu ─────────────────────────────────────────────────────────────
print_main_menu() {
    print_logo
    echo -e "${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║              📋 MAIN MENU                                 ║${NC}"
    echo -e "${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${CYAN}1)${NC} 🚀 Create Tunnel"
    echo -e "  ${CYAN}2)${NC} 🔧 Manage Tunnel"
    echo -e "  ${CYAN}3)${NC} 📦 Update nosrat"
    echo -e "  ${CYAN}4)${NC} 🗑️  Uninstall nosrat"
    echo ""
    echo -e "  ${YELLOW}0)${NC} Exit"
    echo ""
    echo -ne "${BOLD}Choose [0-4]: ${NC}"
}

# ── Create Menu ───────────────────────────────────────────────────────────
print_create_menu() {
    echo ""
    echo -e "${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║              🚀 CREATE TUNNEL                             ║${NC}"
    echo -e "${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${CYAN}1)${NC} 🇮🇷 Iran Server"
    echo -e "  ${CYAN}2)${NC} 🌍 External Server"
    echo ""
    echo -e "  ${YELLOW}0)${NC} Back to Main Menu"
    echo ""
    echo -ne "${BOLD}Choose [0-2]: ${NC}"
}

# ── Manage Menu ───────────────────────────────────────────────────────────
print_manage_menu() {
    echo ""
    echo -e "${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║              🔧 MANAGE TUNNEL                              ║${NC}"
    echo -e "${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${CYAN}1)${NC} 📊 Status"
    echo -e "  ${CYAN}2)${NC} 🏥 Health Check"
    echo -e "  ${CYAN}3)${NC} 🔍 Diagnose"
    echo -e "  ${CYAN}4)${NC} ▶️  Start Tunnel"
    echo -e "  ${CYAN}5)${NC} ⏹️  Stop Tunnel"
    echo -e "  ${CYAN}6)${NC} 🔄 Restart Tunnel"
    echo -e "  ${CYAN}7)${NC} 📜 View Logs"
    echo ""
    echo -e "  ${YELLOW}0)${NC} Back to Main Menu"
    echo ""
    echo -ne "${BOLD}Choose [0-7]: ${NC}"
}

# ── Update Menu ───────────────────────────────────────────────────────────
print_update_menu() {
    echo ""
    echo -e "${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║              📦 UPDATE NOSRAT                              ║${NC}"
    echo -e "${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ── Uninstall Menu ─────────────────────────────────────────────────────────
print_uninstall_menu() {
    echo ""
    echo -e "${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║              🗑️  UNINSTALL NOSRAT                          ║${NC}"
    echo -e "${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════
# CONFIGURATION FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════

# ── Get Iran Server Config ────────────────────────────────────────────────
create_iran_server() {
    echo ""
    echo -e "${BOLD}🇮🇷 Iran Server Configuration${NC}"
    echo ""
    echo -e "${YELLOW}Enter the IP addresses for your tunnel endpoints.${NC}"
    echo ""
    
    # Get Iran IP
    local iran_ip=""
    while [[ -z "$iran_ip" ]]; do
        echo -ne "${CYAN}Enter Iran server public IP: ${NC}"
        read -r iran_ip
        if [[ -z "$iran_ip" ]]; then
            err "IP cannot be empty"
        elif ! [[ "$iran_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            err "Invalid IP format"
            iran_ip=""
        fi
    done
    
    # Get External IP
    local external_ip=""
    while [[ -z "$external_ip" ]]; do
        echo -ne "${CYAN}Enter External server public IP: ${NC}"
        read -r external_ip
        if [[ -z "$external_ip" ]]; then
            err "IP cannot be empty"
        elif ! [[ "$external_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            err "Invalid IP format"
            external_ip=""
        fi
    done
    
    # Generate PSK
    log "Generating PSK..."
    local psk
    psk="$(openssl rand -hex 32 2>/dev/null || head -c 64 /dev/urandom | xxd -p | head -1)"
    
    # Create config directory
    mkdir -p "$CONF_DIR/secrets"
    chmod 0700 "$CONF_DIR/secrets"
    
    # Write PSK
    echo -n "$psk" > "$PSK_FILE"
    chmod 0600 "$PSK_FILE"
    log "PSK generated and saved"
    
    # Write config (Iran side)
    cat > "$CONF_FILE" << EOF
tunnel:
  name: nosrat

local:
  public_ip: "$iran_ip"
  gre_ip: "10.200.0.1/30"

remote:
  public_ip: "$external_ip"
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
    
    log "Configuration saved to $CONF_FILE"
    
    echo ""
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}📋 Configuration Summary (Iran Server)${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${CYAN}Iran IP:      ${NC}$iran_ip"
    echo -e "  ${CYAN}External IP:  ${NC}$external_ip"
    echo -e "  ${CYAN}Local GRE:    ${NC}10.200.0.1/30"
    echo -e "  ${CYAN}Remote GRE:   ${NC}10.200.0.2/30"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    echo -e "${YELLOW}⚠️  Copy this PSK to the EXTERNAL server:${NC}"
    echo ""
    echo -e "    ${BOLD}$psk${NC}"
    echo ""
    echo -e "${YELLOW}Run this on the external server:${NC}"
    echo -e "    ${CYAN}echo '$psk' | sudo tee /etc/nosrat/secrets/psk${NC}"
    echo -e "    ${CYAN}sudo chmod 600 /etc/nosrat/secrets/psk${NC}"
    echo ""
    
    read -n 1 -s -r -p "Press any key to continue..."
}

# ── Get External Server Config ─────────────────────────────────────────────
create_external_server() {
    echo ""
    echo -e "${BOLD}🌍 External Server Configuration${NC}"
    echo ""
    echo -e "${YELLOW}Enter the public IP and PSK from your Iran server.${NC}"
    echo ""
    
    # Get External IP
    local external_ip=""
    while [[ -z "$external_ip" ]]; do
        echo -ne "${CYAN}Enter External server public IP: ${NC}"
        read -r external_ip
        if [[ -z "$external_ip" ]]; then
            err "IP cannot be empty"
        elif ! [[ "$external_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            err "Invalid IP format"
            external_ip=""
        fi
    done
    
    # Get PSK
    local psk=""
    while [[ -z "$psk" ]]; do
        echo -ne "${CYAN}Enter PSK (from Iran server): ${NC}"
        read -r psk
        if [[ -z "$psk" ]]; then
            err "PSK cannot be empty"
        elif [[ ${#psk} -lt 32 ]]; then
            err "PSK too short (need at least 32 characters)"
            psk=""
        fi
    done
    
    # Create config directory
    mkdir -p "$CONF_DIR/secrets"
    chmod 0700 "$CONF_DIR/secrets"
    
    # Write PSK
    echo -n "$psk" > "$PSK_FILE"
    chmod 0600 "$PSK_FILE"
    log "PSK saved"
    
    # Write config (External side)
    cat > "$CONF_FILE" << EOF
tunnel:
  name: nosrat

local:
  public_ip: "$external_ip"
  gre_ip: "10.200.0.2/30"

remote:
  public_ip: "IRAN_SERVER_IP"
  gre_ip: "10.200.0.1/30"

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
    
    log "Configuration saved to $CONF_FILE"
    
    echo ""
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}📋 Configuration Summary (External Server)${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${CYAN}External IP: ${NC}$external_ip"
    echo -e "  ${CYAN}Local GRE:   ${NC}10.200.0.2/30"
    echo -e "  ${CYAN}Remote GRE:  ${NC}10.200.0.1/30 (IRAN_SERVER_IP placeholder)"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}⚠️  Important: Edit the config to set the actual Iran server IP:${NC}"
    echo -e "    ${CYAN}sudo nano /etc/nosrat/tunnel.yaml${NC}"
    echo -e "    Change ${BOLD}IRAN_SERVER_IP${NC} to your actual Iran server IP"
    echo ""
    
    read -n 1 -s -r -p "Press any key to continue..."
}

# ═══════════════════════════════════════════════════════════════════════════
# ACTION HANDLERS
# ═══════════════════════════════════════════════════════════════════════════

# ── Create Tunnel Flow ────────────────────────────────────────────────────
do_create_tunnel() {
    while true; do
        print_create_menu
        read -r choice
        
        case "$choice" in
            1)
                create_iran_server
                return
                ;;
            2)
                create_external_server
                return
                ;;
            0)
                return
                ;;
            *)
                err "Invalid choice"
                sleep 1
                ;;
        esac
    done
}

# ── Manage Tunnel Flow ────────────────────────────────────────────────────
do_manage_tunnel() {
    while true; do
        print_manage_menu
        read -r choice
        
        case "$choice" in
            1)
                echo ""
                echo -e "${BOLD}📊 Tunnel Status${NC}"
                echo ""
                "$NOSRAT_BIN" status 2>/dev/null || err "Could not get status"
                ;;
            2)
                echo ""
                echo -e "${BOLD}🏥 Health Check${NC}"
                echo ""
                "$NOSRAT_BIN" health 2>/dev/null || err "Could not run health check"
                ;;
            3)
                echo ""
                echo -e "${BOLD}🔍 Diagnose${NC}"
                echo ""
                "$NOSRAT_BIN" diagnose 2>/dev/null || err "Could not run diagnose"
                ;;
            4)
                echo ""
                echo -e "${BOLD}▶️ Starting Tunnel${NC}"
                echo ""
                "$NOSRAT_BIN" start 2>/dev/null && log "Tunnel started" || err "Failed to start tunnel"
                ;;
            5)
                echo ""
                echo -e "${BOLD}⏹️ Stopping Tunnel${NC}"
                echo ""
                "$NOSRAT_BIN" stop 2>/dev/null && log "Tunnel stopped" || err "Failed to stop tunnel"
                ;;
            6)
                echo ""
                echo -e "${BOLD}🔄 Restarting Tunnel${NC}"
                echo ""
                "$NOSRAT_BIN" restart 2>/dev/null && log "Tunnel restarted" || err "Failed to restart tunnel"
                ;;
            7)
                echo ""
                echo -e "${BOLD}📜 Recent Logs${NC}"
                echo ""
                journalctl -u nosrat -u strongswan -n 50 --no-pager 2>/dev/null || err "Could not read logs"
                ;;
            0)
                return
                ;;
            *)
                err "Invalid choice"
                sleep 1
                ;;
        esac
        
        echo ""
        read -n 1 -s -r -p "Press any key to continue..."
    done
}

# ── Update nosrat ──────────────────────────────────────────────────────────
do_update() {
    print_update_menu
    
    if [[ ! -d "/opt/nosrat/.git" ]] && [[ ! -d "/root/nosrat/.git" ]]; then
        warn "nosrat was not installed from source"
        echo ""
        echo -e "${YELLOW}Please reinstall using:${NC}"
        echo -e "    ${CYAN}curl -sL https://raw.githubusercontent.com/pdnczone/nosrat/main/install.sh | sudo bash${NC}"
        echo ""
        read -n 1 -s -r -p "Press any key to continue..."
        return
    fi
    
    echo ""
    echo -e "${CYAN}Checking for updates...${NC}"
    
    local repo_dir=""
    if [[ -d "/opt/nosrat/.git" ]]; then
        repo_dir="/opt/nosrat"
    elif [[ -d "/root/nosrat/.git" ]]; then
        repo_dir="/root/nosrat"
    fi
    
    if [[ -n "$repo_dir" ]]; then
        ( cd "$repo_dir" && git pull --rebase 2>/dev/null || true )
        log "Source updated"
        
        # Rebuild
        ( cd "$repo_dir" && CGO_ENABLED=0 go build -o "$NOSRAT_BIN" ./cmd/nosrat 2>/dev/null ) && \
            log "Binary updated" || err "Build failed"
    fi
    
    echo ""
    read -n 1 -s -r -p "Press any key to continue..."
}

# ── Uninstall nosrat ───────────────────────────────────────────────────────
do_uninstall() {
    print_uninstall_menu
    
    warn "This will remove nosrat, all configurations, and stop the tunnel."
    echo ""
    read -p "Are you sure? Type 'yes' to confirm: " confirm
    
    if [[ "$confirm" != "yes" ]]; then
        log "Cancelled"
        sleep 2
        return
    fi
    
    echo ""
    log "Stopping tunnel..."
    "$NOSRAT_BIN" stop 2>/dev/null || true
    
    log "Removing firewall rules..."
    "$NOSRAT_BIN" uninstall 2>/dev/null || true
    
    log "Removing systemd service..."
    systemctl stop nosrat 2>/dev/null || true
    systemctl disable nosrat 2>/dev/null || true
    rm -f /etc/systemd/system/nosrat.service
    systemctl daemon-reload
    
    log "Removing binary..."
    rm -f "$NOSRAT_BIN"
    
    read -p "Remove configuration and PSK? [y/N]: " remove_config
    if [[ "$remove_config" =~ ^[Yy]$ ]]; then
        log "Removing configuration..."
        rm -rf "$CONF_DIR"
    fi
    
    echo ""
    log "Uninstall complete"
    echo ""
    echo -e "${YELLOW}Note: source code (if cloned to /opt/nosrat or ~/nosrat) is preserved${NC}"
    echo ""
    exit 0
}

# ═══════════════════════════════════════════════════════════════════════════
# MAIN LOOP
# ═══════════════════════════════════════════════════════════════════════════

# ── Check if nosrat is installed ───────────────────────────────────────────
if [[ ! -x "$NOSRAT_BIN" ]]; then
    err "nosrat binary not found at $NOSRAT_BIN"
    echo ""
    echo -e "${YELLOW}Please run the installer first:${NC}"
    echo -e "    ${CYAN}curl -sL https://raw.githubusercontent.com/pdnczone/nosrat/main/install.sh | sudo bash${NC}"
    echo ""
    exit 1
fi

# ── Check if config exists ─────────────────────────────────────────────────
if [[ ! -f "$CONF_FILE" ]]; then
    warn "Configuration not found at $CONF_FILE"
    echo ""
    echo -e "${YELLOW}Please run 'Create Tunnel' first to set up your configuration.${NC}"
    echo ""
fi

# ── Main menu loop ────────────────────────────────────────────────────────
while true; do
    print_main_menu
    read -r choice
    
    case "$choice" in
        1) do_create_tunnel ;;
        2) do_manage_tunnel ;;
        3) do_update ;;
        4) do_uninstall ;;
        0)
            echo ""
            log "Goodbye! 👋"
            echo ""
            exit 0
            ;;
        *)
            err "Invalid choice"
            sleep 1
            ;;
    esac
done
