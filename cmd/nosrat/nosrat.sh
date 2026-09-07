#!/usr/bin/env bash
# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║  ███╗   ██╗  ██████╗ ███████╗ ██████╗  █████╗ ████████╗                   ║
# ║  ████╗  ██║██╔═══██╗██╔════╝██╔═══██╗██╔══██╗╚══██╔══╝                   ║
# ║  ██╔██╗ ██║██║   ██║███████╗██║   ██║███████║   ██║                      ║
# ║  ██║╚██╗██║██║   ██║╚════██║██║   ██║██╔══██║   ██║                      ║
# ║  ██║ ╚████║╚██████╔╝███████║╚██████╔╝██║  ██║   ██║                      ║
# ║  ╚═╝  ╚═══╝ ╚═════╝ ╚══════╝ ╚═════╝ ╚═╝  ╚═╝   ╚═╝                      ║
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
    ███╗   ██╗  ██████╗ ███████╗ ██████╗  █████╗ ████████╗
    ████╗  ██║██╔═══██╗██╔════╝██╔═══██╗██╔══██╗╚══██╔══╝
    ██╔██╗ ██║██║   ██║███████╗██║   ██║███████║   ██║
    ██║╚██╗██║██║   ██║╚════██║██║   ██║██╔══██║   ██║
    ██║ ╚████║╚██████╔╝███████║╚██████╔╝██║  ██║   ██║
    ╚═╝  ╚═══╝ ╚═════╝ ╚══════╝ ╚═════╝ ╚═╝  ╚═╝   ╚═╝
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
    echo -e "  ${CYAN}3)${NC} 🔐 Crypto / Encryption"
    echo -e "  ${CYAN}4)${NC} 🏥 Health Check"
    echo -e "  ${CYAN}5)${NC} 🚄 Speed Test"
    echo -e "  ${CYAN}6)${NC} 📦 Update nosrat"
    echo -e "  ${CYAN}7)${NC} 🗑️  Uninstall nosrat"
    echo ""
    echo -e "  ${YELLOW}0)${NC} Exit"
    echo ""
    echo -ne "${BOLD}Choose [0-7]: ${NC}"
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
    echo -e "  ${CYAN}2)${NC} 🔍 Diagnose"
    echo -e "  ${CYAN}3)${NC} ▶️  Start Tunnel"
    echo -e "  ${CYAN}4)${NC} ⏹️  Stop Tunnel"
    echo -e "  ${CYAN}5)${NC} 🔄 Restart Tunnel"
    echo -e "  ${CYAN}6)${NC} 📜 View Logs"
    echo ""
    echo -e "  ${YELLOW}0)${NC} Back to Main Menu"
    echo ""
    echo -ne "${BOLD}Choose [0-6]: ${NC}"
}

# ── Crypto Menu ───────────────────────────────────────────────────────────
print_crypto_menu() {
    echo ""
    echo -e "${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║              🔐 CRYPTO / ENCRYPTION                       ║${NC}"
    echo -e "${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${CYAN}1)${NC} 🔑 Generate new PSK (256-bit, recommended)"
    echo -e "  ${CYAN}2)${NC} 🔐 Generate strong PSK (512-bit)"
    echo -e "  ${CYAN}3)${NC} 🔄 Regenerate PSK (rotate keys)"
    echo -e "  ${CYAN}4)${NC} 👁️  View current PSK (masked)"
    echo -e "  ${CYAN}5)${NC} ⚙️  Change encryption algorithm"
    echo ""
    echo -e "  ${YELLOW}0)${NC} Back to Main Menu"
    echo ""
    echo -ne "${BOLD}Choose [0-5]: ${NC}"
}

# ── Health Menu ───────────────────────────────────────────────────────────
print_health_menu() {
    echo ""
    echo -e "${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║              🏥 HEALTH CHECK                              ║${NC}"
    echo -e "${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${CYAN}1)${NC} 🩺 Quick health check"
    echo -e "  ${CYAN}2)${NC} 🔬 Detailed diagnostic"
    echo -e "  ${CYAN}3)${NC} 🔁 Continuous monitoring (10s)"
    echo ""
    echo -e "  ${YELLOW}0)${NC} Back to Main Menu"
    echo ""
    echo -ne "${BOLD}Choose [0-3]: ${NC}"
}

# ── Speed Test Menu ───────────────────────────────────────────────────────
print_speed_menu() {
    echo ""
    echo -e "${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║              🚄 SPEED TEST                                ║${NC}"
    echo -e "${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${CYAN}1)${NC} 📡 Ping latency (Iran ↔ External)"
    echo -e "  ${CYAN}2)${NC} 🚀 Full speed test (ping + throughput)"
    echo -e "  ${CYAN}3)${NC} 📊 iperf3 test (if available)"
    echo ""
    echo -e "  ${YELLOW}0)${NC} Back to Main Menu"
    echo ""
    echo -ne "${BOLD}Choose [0-3]: ${NC}"
}

# ═══════════════════════════════════════════════════════════════════════════
# CONFIGURATION FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════

# ── Generate PSK (optional, helper) ───────────────────────────────────────
generate_psk() {
    local bits="${1:-256}"
    if [[ "$bits" == "512" ]]; then
        openssl rand -hex 64 2>/dev/null || head -c 128 /dev/urandom | xxd -p | head -1
    else
        openssl rand -hex 32 2>/dev/null || head -c 64 /dev/urandom | xxd -p | head -1
    fi
}

# ── Ask user if they want PSK ─────────────────────────────────────────────
ask_psk() {
    local psk=""
    echo ""
    echo -e "${YELLOW}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║  🔐 Pre-Shared Key (PSK) Configuration                    ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${CYAN}1)${NC} Generate new 256-bit PSK (recommended) ⭐"
    echo -e "  ${CYAN}2)${NC} Generate strong 512-bit PSK"
    echo -e "  ${CYAN}3)${NC} Enter existing PSK manually"
    echo -e "  ${CYAN}4)${NC} Skip PSK setup (tunnel works without it) ⚠️"
    echo ""
    echo -e "  ${YELLOW}Note: Without PSK, IPsec will use a default placeholder.${NC}"
    echo -e "  ${YELLOW}      For production use, a real PSK is strongly recommended.${NC}"
    echo ""
    echo -ne "${BOLD}Choose [1-4]: ${NC}"
    read -r psk_choice
    
    case "$psk_choice" in
        1)
            psk="$(generate_psk 256)"
            log "256-bit PSK generated"
            ;;
        2)
            psk="$(generate_psk 512)"
            log "512-bit PSK generated"
            ;;
        3)
            while [[ -z "$psk" ]]; do
                echo -ne "${CYAN}Enter PSK (min 32 chars): ${NC}"
                read -r psk
                if [[ ${#psk} -lt 32 ]]; then
                    err "PSK too short (need at least 32 characters)"
                    psk=""
                fi
            done
            log "Custom PSK accepted"
            ;;
        4)
            warn "Skipping PSK — using placeholder"
            psk="PLACEHOLDER_REPLACE_ME_$(date +%s)"
            ;;
        *)
            err "Invalid choice, using 256-bit PSK"
            psk="$(generate_psk 256)"
            ;;
    esac
    
    echo "$psk"
}

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
    
    # Create config directory
    mkdir -p "$CONF_DIR/secrets"
    chmod 0700 "$CONF_DIR/secrets"
    
    # Ask about PSK
    local psk
    psk="$(ask_psk)"
    
    # Write PSK
    echo -n "$psk" > "$PSK_FILE"
    chmod 0600 "$PSK_FILE"
    log "PSK saved to $PSK_FILE"
    
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
        echo -ne "${CYAN}Enter PSK (from Iran server, min 32 chars): ${NC}"
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
# CRYPTO FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════

do_crypto() {
    while true; do
        print_crypto_menu
        read -r choice
        
        case "$choice" in
            1)
                echo ""
                echo -e "${BOLD}🔑 Generate 256-bit PSK${NC}"
                echo ""
                
                if [[ -f "$PSK_FILE" ]]; then
                    warn "Existing PSK found. This will overwrite it."
                    read -p "Continue? [y/N]: " confirm
                    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                        log "Cancelled"
                        sleep 1
                        continue
                    fi
                fi
                
                mkdir -p "$(dirname "$PSK_FILE")"
                chmod 0700 "$(dirname "$PSK_FILE")"
                
                local new_psk
                new_psk="$(generate_psk 256)"
                echo -n "$new_psk" > "$PSK_FILE"
                chmod 0600 "$PSK_FILE"
                log "New 256-bit PSK generated and saved"
                echo ""
                echo -e "${YELLOW}PSK (save this!):${NC}"
                echo -e "    ${BOLD}$new_psk${NC}"
                echo ""
                echo -e "${CYAN}Copy this PSK to the other server too.${NC}"
                ;;
            2)
                echo ""
                echo -e "${BOLD}🔐 Generate 512-bit PSK${NC}"
                echo ""
                
                if [[ -f "$PSK_FILE" ]]; then
                    warn "Existing PSK found. This will overwrite it."
                    read -p "Continue? [y/N]: " confirm
                    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                        log "Cancelled"
                        sleep 1
                        continue
                    fi
                fi
                
                mkdir -p "$(dirname "$PSK_FILE")"
                chmod 0700 "$(dirname "$PSK_FILE")"
                
                local new_psk
                new_psk="$(generate_psk 512)"
                echo -n "$new_psk" > "$PSK_FILE"
                chmod 0600 "$PSK_FILE"
                log "New 512-bit PSK generated and saved"
                echo ""
                echo -e "${YELLOW}PSK (save this!):${NC}"
                echo -e "    ${BOLD}$new_psk${NC}"
                echo ""
                echo -e "${CYAN}Copy this PSK to the other server too.${NC}"
                ;;
            3)
                echo ""
                echo -e "${BOLD}🔄 Regenerate PSK (Rotate Keys)${NC}"
                echo ""
                warn "This will:"
                echo "    1. Generate a new PSK"
                echo "    2. Overwrite the current PSK"
                echo "    3. Disrupt active tunnel connections"
                echo ""
                read -p "Are you sure? [y/N]: " confirm
                if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                    log "Cancelled"
                    sleep 1
                    continue
                fi
                
                # Stop tunnel if running
                "$NOSRAT_BIN" stop 2>/dev/null || true
                
                local new_psk
                new_psk="$(generate_psk 256)"
                echo -n "$new_psk" > "$PSK_FILE"
                chmod 0600 "$PSK_FILE"
                log "PSK rotated"
                echo ""
                echo -e "${YELLOW}New PSK (copy to other server):${NC}"
                echo -e "    ${BOLD}$new_psk${NC}"
                echo ""
                warn "Don't forget to update the PSK on the other server too!"
                ;;
            4)
                echo ""
                echo -e "${BOLD}👁️  Current PSK (masked)${NC}"
                echo ""
                if [[ ! -f "$PSK_FILE" ]]; then
                    warn "No PSK file found"
                else
                    local psk_len
                    psk_len=$(wc -c < "$PSK_FILE")
                    local first_chars
                    first_chars=$(head -c 8 "$PSK_FILE")
                    local last_chars
                    last_chars=$(tail -c 8 "$PSK_FILE")
                    echo -e "  ${CYAN}Length:${NC} $psk_len characters"
                    echo -e "  ${CYAN}Preview:${NC} ${first_chars}...${last_chars}"
                    echo -e "  ${CYAN}Location:${NC} $PSK_FILE"
                    echo -e "  ${CYAN}Permissions:${NC} $(stat -c '%a' "$PSK_FILE")"
                    echo ""
                    echo -e "${YELLOW}To view full PSK, run: sudo cat $PSK_FILE${NC}"
                fi
                ;;
            5)
                echo ""
                echo -e "${BOLD}⚙️  Change Encryption Algorithm${NC}"
                echo ""
                echo "  1) aes256gcm16 (default, recommended)"
                echo "  2) aes128gcm16"
                echo "  3) chacha20poly1305"
                echo ""
                read -p "Choose [1-3]: " algo_choice
                local algo
                case "$algo_choice" in
                    1) algo="aes256gcm16" ;;
                    2) algo="aes128gcm16" ;;
                    3) algo="chacha20poly1305" ;;
                    *) err "Invalid choice"; sleep 1; continue ;;
                esac
                
                if [[ -f "$CONF_FILE" ]]; then
                    sed -i "s/encryption: .*/encryption: $algo/" "$CONF_FILE"
                    log "Encryption algorithm set to: $algo"
                    
                    # Restart tunnel
                    warn "Restarting tunnel to apply changes..."
                    "$NOSRAT_BIN" restart 2>/dev/null && log "Tunnel restarted" || warn "Restart needed manually"
                else
                    err "Config file not found. Create tunnel first."
                fi
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

# ═══════════════════════════════════════════════════════════════════════════
# HEALTH CHECK FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════

do_health() {
    while true; do
        print_health_menu
        read -r choice
        
        case "$choice" in
            1)
                echo ""
                echo -e "${BOLD}🩺 Quick Health Check${NC}"
                echo ""
                echo -e "${CYAN}→ GRE interface:${NC}"
                ip link show nosrat 2>/dev/null | head -3 || err "  GRE interface not found"
                echo ""
                echo -e "${CYAN}→ IPsec SA:${NC}"
                ip xfrm state 2>/dev/null | head -5 || err "  No IPsec SA"
                echo ""
                echo -e "${CYAN}→ Tunnel endpoint reachable:${NC}"
                if [[ -f "$CONF_FILE" ]]; then
                    local remote_ip
                    remote_ip=$(grep -A2 "remote:" "$CONF_FILE" | grep "public_ip:" | sed 's/.*"\(.*\)".*/\1/')
                    if [[ -n "$remote_ip" ]] && [[ "$remote_ip" != "IRAN_SERVER_IP" ]]; then
                        ping -c 2 -W 2 "$remote_ip" 2>&1 | tail -3
                    else
                        warn "  Remote IP not configured"
                    fi
                fi
                echo ""
                echo -e "${CYAN}→ Service status:${NC}"
                systemctl is-active nosrat 2>/dev/null && log "  nosrat: active" || warn "  nosrat: inactive"
                systemctl is-active strongswan 2>/dev/null && log "  strongswan: active" || warn "  strongswan: inactive"
                ;;
            2)
                echo ""
                echo -e "${BOLD}🔬 Detailed Diagnostic${NC}"
                echo ""
                "$NOSRAT_BIN" diagnose 2>/dev/null || err "Could not run diagnose"
                ;;
            3)
                echo ""
                echo -e "${BOLD}🔁 Continuous Monitoring (10s)${NC}"
                echo ""
                echo -e "${YELLOW}Press Ctrl+C to stop${NC}"
                echo ""
                for i in {1..10}; do
                    echo -e "${CYAN}[$i/10] $(date +%H:%M:%S)${NC}"
                    
                    # Check GRE
                    if ip link show nosrat &>/dev/null; then
                        echo "  ✓ GRE interface UP"
                    else
                        echo "  ✗ GRE interface DOWN"
                    fi
                    
                    # Check IPsec
                    if ip xfrm state | grep -q "esp"; then
                        echo "  ✓ IPsec SA active"
                    else
                        echo "  ✗ IPsec SA missing"
                    fi
                    
                    # Check service
                    if systemctl is-active nosrat &>/dev/null; then
                        echo "  ✓ nosrat service running"
                    else
                        echo "  ✗ nosrat service stopped"
                    fi
                    
                    # Check connectivity
                    if [[ -f "$CONF_FILE" ]]; then
                        local remote_ip
                        remote_ip=$(grep -A2 "remote:" "$CONF_FILE" | grep "public_ip:" | sed 's/.*"\(.*\)".*/\1/')
                        if [[ -n "$remote_ip" ]] && [[ "$remote_ip" != "IRAN_SERVER_IP" ]]; then
                            local loss
                            loss=$(ping -c 1 -W 2 "$remote_ip" 2>/dev/null | grep -oP '\d+(?=% packet loss)' || echo "100")
                            echo "  ${CYAN}→ Packet loss to remote: ${loss}%${NC}"
                        fi
                    fi
                    
                    echo ""
                    sleep 1
                done
                log "Monitoring complete"
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

# ═══════════════════════════════════════════════════════════════════════════
# SPEED TEST FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════

do_speed_test() {
    while true; do
        print_speed_menu
        read -r choice
        
        case "$choice" in
            1)
                echo ""
                echo -e "${BOLD}📡 Ping Latency Test${NC}"
                echo ""
                
                if [[ ! -f "$CONF_FILE" ]]; then
                    err "No config found. Create tunnel first."
                    sleep 2
                    continue
                fi
                
                local remote_ip
                remote_ip=$(grep -A2 "remote:" "$CONF_FILE" | grep "public_ip:" | sed 's/.*"\(.*\)".*/\1/')
                
                if [[ -z "$remote_ip" ]] || [[ "$remote_ip" == "IRAN_SERVER_IP" ]]; then
                    err "Remote IP not configured. Edit /etc/nosrat/tunnel.yaml"
                    sleep 2
                    continue
                fi
                
                echo -e "${CYAN}Testing latency to $remote_ip...${NC}"
                echo ""
                ping -c 10 -i 0.5 "$remote_ip" 2>&1
                ;;
            2)
                echo ""
                echo -e "${BOLD}🚀 Full Speed Test${NC}"
                echo ""
                echo -e "${YELLOW}This will: 1) Ping 2) Transfer 50MB test file via tunnel${NC}"
                echo ""
                
                if [[ ! -f "$CONF_FILE" ]]; then
                    err "No config found. Create tunnel first."
                    sleep 2
                    continue
                fi
                
                local remote_ip
                remote_ip=$(grep -A2 "remote:" "$CONF_FILE" | grep "public_ip:" | sed 's/.*"\(.*\)".*/\1/')
                
                if [[ -z "$remote_ip" ]] || [[ "$remote_ip" == "IRAN_SERVER_IP" ]]; then
                    err "Remote IP not configured. Edit /etc/nosrat/tunnel.yaml"
                    sleep 2
                    continue
                fi
                
                # Step 1: Ping
                echo -e "${CYAN}━━━ Step 1/2: Latency Test ━━━${NC}"
                echo ""
                ping -c 5 -i 0.5 "$remote_ip" 2>&1 | tail -7
                echo ""
                
                # Step 2: Throughput
                echo -e "${CYAN}━━━ Step 2/2: Throughput Test ━━━${NC}"
                echo ""
                
                # Check if GRE tunnel is up
                if ! ip link show nosrat &>/dev/null; then
                    err "GRE tunnel not up. Start tunnel first."
                    sleep 2
                    continue
                fi
                
                local gre_remote
                gre_remote=$(grep -A2 "remote:" "$CONF_FILE" | grep "gre_ip:" | sed 's/.*"\(.*\)".*/\1' | cut -d/ -f1)
                
                if [[ -z "$gre_remote" ]]; then
                    err "Could not determine GRE remote IP"
                    sleep 2
                    continue
                fi
                
                echo -e "${CYAN}Testing throughput to $gre_remote (tunnel endpoint)...${NC}"
                echo ""
                
                # Generate 50MB test file and measure transfer via netcat or /dev/zero
                # Use dd + nc if available, otherwise use simple ping-based estimate
                if command -v nc &>/dev/null; then
                    echo -e "${YELLOW}Note: For accurate test, run on both servers:${NC}"
                    echo -e "  ${CYAN}Server 1: nc -l -p 9999 > /dev/null${NC}"
                    echo -e "  ${CYAN}Server 2: dd if=/dev/zero bs=1M count=50 | nc -w 5 <peer> 9999${NC}"
                    echo ""
                    echo -e "${YELLOW}Or install 'iperf3' and run 'iperf3 -c <peer>' on one side${NC}"
                    echo ""
                    
                    # Try simple test with /dev/zero to /dev/null via nc
                    echo -e "${CYAN}Attempting 10MB test (requires nc on remote)...${NC}"
                    timeout 10 dd if=/dev/zero bs=1M count=10 2>/dev/null | nc -w 5 "$gre_remote" 9999 2>&1 | head -3 || \
                        warn "Could not connect to remote listener. Start listener on remote first."
                else
                    warn "nc (netcat) not installed. Install with: apt install netcat-openbsd"
                fi
                ;;
            3)
                echo ""
                echo -e "${BOLD}📊 iperf3 Speed Test${NC}"
                echo ""
                
                if ! command -v iperf3 &>/dev/null; then
                    err "iperf3 not installed"
                    echo ""
                    echo -e "${YELLOW}Install with: sudo apt install iperf3${NC}"
                    sleep 3
                    continue
                fi
                
                if [[ ! -f "$CONF_FILE" ]]; then
                    err "No config found. Create tunnel first."
                    sleep 2
                    continue
                fi
                
                local remote_ip
                remote_ip=$(grep -A2 "remote:" "$CONF_FILE" | grep "public_ip:" | sed 's/.*"\(.*\)".*/\1/')
                
                if [[ -z "$remote_ip" ]] || [[ "$remote_ip" == "IRAN_SERVER_IP" ]]; then
                    err "Remote IP not configured"
                    sleep 2
                    continue
                fi
                
                echo -e "${CYAN}→ Run on the OTHER server first: iperf3 -s${NC}"
                echo ""
                read -p "Press Enter when iperf3 server is ready on the other side..."
                echo ""
                echo -e "${CYAN}Running iperf3 test to $remote_ip...${NC}"
                echo ""
                iperf3 -c "$remote_ip" -t 10 -P 4 2>&1
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
                echo -e "${BOLD}🔍 Diagnose${NC}"
                echo ""
                "$NOSRAT_BIN" diagnose 2>/dev/null || err "Could not run diagnose"
                ;;
            3)
                echo ""
                echo -e "${BOLD}▶️ Starting Tunnel${NC}"
                echo ""
                "$NOSRAT_BIN" start 2>/dev/null && log "Tunnel started" || err "Failed to start tunnel"
                ;;
            4)
                echo ""
                echo -e "${BOLD}⏹️ Stopping Tunnel${NC}"
                echo ""
                "$NOSRAT_BIN" stop 2>/dev/null && log "Tunnel stopped" || err "Failed to stop tunnel"
                ;;
            5)
                echo ""
                echo -e "${BOLD}🔄 Restarting Tunnel${NC}"
                echo ""
                "$NOSRAT_BIN" restart 2>/dev/null && log "Tunnel restarted" || err "Failed to restart tunnel"
                ;;
            6)
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
    echo ""
    echo -e "${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║              🗑️  UNINSTALL NOSRAT                          ║${NC}"
    echo -e "${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
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
# (No-op for now; the script is the actual binary)

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
        3) do_crypto ;;
        4) do_health ;;
        5) do_speed_test ;;
        6) do_update ;;
        7) do_uninstall ;;
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
