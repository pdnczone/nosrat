#!/bin/bash
# GhostTunnel installer — generalized for nosrat integration
# WireGuard + Cloak + Nginx with path rotation
#
# Configuration is read from /etc/ghosttunnel/config.sh (sourced at runtime).
# This script self-installs all its own dependencies and never modifies the
# main nosrat package list.

set -e

# --- Detect source location ---
# When invoked from the nosrat menu, we run from /tmp/ghosttunnel-install/.
# The caller has already cloned scripts there. We use dirname to locate them.
INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$INSTALL_DIR/scripts"

# --- Load helpers ---
# shellcheck disable=SC1091
source "$SCRIPTS_DIR/helpers.sh"

# --- Load user configuration (must exist) ---
GHOST_CONFIG="${GHOST_CONFIG:-/etc/ghosttunnel/config.sh}"
if [[ ! -f "$GHOST_CONFIG" ]]; then
  echo "ERROR: configuration not found at $GHOST_CONFIG" >&2
  echo "       Run 'nosrat -> Create Tunnel -> Ghost Tunnel' to create it." >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$GHOST_CONFIG"
check_error "Failed to load $GHOST_CONFIG"

# === 1. Root check ===
if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: this script must be run with root privileges" >&2
  exit 1
fi

# === 2. Package manager detection (no Ubuntu-only check) ===
detect_pkg_mgr

# === 3. Install GhostTunnel dependencies (isolated from nosrat) ===
status "Installing GhostTunnel dependencies (this may take a few minutes)"
case "$PKG_MGR" in
  apt)
    DEBIAN_FRONTEND=noninteractive apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      wireguard wireguard-tools resolvconf jq openssl iptables-persistent \
      curl git qrencode nginx certbot python3-certbot-nginx bc ca-certificates
    ;;
  dnf|yum)
    # RHEL family. wireguard-tools provides `wg` and `wg-quick`. The kernel
    # module needs to be loaded via dkms/kmod-wireguard on RHEL — we install
    # kmod-wireguard if available, otherwise the user must enable a kernel module.
    $PKG_MGR install -y epel-release || true
    $PKG_MGR install -y \
      wireguard-tools jq openssl iptables-services \
      curl git qrencode nginx certbot python3-certbot-nginx bc ca-certificates \
      kmod-wireguard wireguard-dkms || true
    ;;
esac
check_error "Failed to install GhostTunnel prerequisite packages."

# Disable services that conflict (best-effort, ignore failures)
systemctl disable --now apparmor ufw snapd 2>/dev/null || true

# === 4. Gather additional user input ===
status "Gathering connection details"
read -p "Do you have a custom domain? (y/N) " USE_DOMAIN
if [[ "$USE_DOMAIN" =~ ^[Yy]$ ]]; then
  while [[ -z "${DOMAIN_NAME:-}" ]]; do
    read -p "Enter your domain name: " DOMAIN_NAME
  done
  read -p "Email address for SSL certificate (Let's Encrypt notices): " EMAIL
  SERVER_NAME="$DOMAIN_NAME"
else
  SERVER_NAME=$(curl -s --max-time 10 ifconfig.me || echo "")
  DOMAIN_NAME=""
  EMAIL=""
fi

if [[ -z "$SERVER_NAME" ]]; then
  echo "ERROR: could not determine SERVER_NAME and no domain provided" >&2
  exit 1
fi

# === 5. Run setup modules ===
status "Starting modular setup..."

# Each module is invoked with explicit absolute paths so it works regardless
# of current working directory.
"$SCRIPTS_DIR/setup_firewall.sh"
"$SCRIPTS_DIR/setup_cloak.sh" "$CLOAK_REDIR"
"$SCRIPTS_DIR/setup_wireguard.sh" "$VPN_USERS" "$SERVER_NAME" "$DNS_SERVER"
"$SCRIPTS_DIR/setup_nginx_and_ssl.sh" "$SERVER_NAME" "$DOMAIN_NAME" "$EMAIL"
"$SCRIPTS_DIR/setup_monitoring.sh" "$PATH_ROTATION_INTERVAL"

# === 6. Deployment complete ===
status "Deployment completed successfully!"
echo "================================================"
echo " GhostTunnel Server Information"
echo "================================================"
echo "  Connection address:   $SERVER_NAME"
echo "  Cloak port:           443"
echo "  Current VPN path:     $(cat /var/www/html/current-path 2>/dev/null || echo 'N/A')"
echo ""
echo "  === Client Information ==="
echo "  Config files:         /etc/wireguard/clients/"
echo "  QR Codes (PNG):       /etc/wireguard/clients/"
echo ""
echo "  === Management Commands ==="
echo "  Rotate VPN path:      sudo /usr/local/bin/rotate-path.sh"
echo "  Check status:         systemctl status cloak wg-quick@wg0 nginx"
echo "  View monitor logs:    tail -f /var/log/vpn-monitor.log"
echo "================================================"

exit 0