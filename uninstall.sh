#!/usr/bin/env bash
# nosrat (PDNC) uninstaller - removes the service, binary, firewall rules and GRE
# interface. Config (/etc/nosrat) and the PSK are kept unless --purge is passed.
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "run as root (sudo ./uninstall.sh [--purge])" >&2; exit 1; }

PURGE=false
[[ "${1:-}" == "--purge" ]] && PURGE=true

echo "[uninstall] stopping and disabling nosrat service"
systemctl stop nosrat 2>/dev/null || true
systemctl disable nosrat 2>/dev/null || true

if command -v nosrat >/dev/null 2>&1; then
  echo "[uninstall] tearing down tunnel resources (GRE, IPsec, firewall)"
  nosrat uninstall || true
fi

echo "[uninstall] removing systemd unit"
rm -f /etc/systemd/system/nosrat.service
systemctl daemon-reload

echo "[uninstall] removing binary"
rm -f /usr/local/bin/nosrat

if $PURGE; then
  echo "[uninstall] --purge: removing /etc/nosrat (config + PSK) and swanctl conf.d entries"
  rm -rf /etc/nosrat
  rm -f /etc/swanctl/conf.d/*.conf
else
  echo "[uninstall] keeping /etc/nosrat (config + PSK). Re-run with --purge to remove it too."
fi

echo "[uninstall] done."
