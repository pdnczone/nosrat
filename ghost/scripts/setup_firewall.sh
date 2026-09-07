#!/bin/bash
# Firewall and Kernel Hardening Setup (generalized for nosrat)

source ./scripts/helpers.sh

status "Configuring basic security"

# Kernel security settings (idempotent: only append if not present)
if ! grep -q "^net.ipv4.icmp_echo_ignore_all=1" /etc/sysctl.conf 2>/dev/null; then
cat >> /etc/sysctl.conf <<EOF
net.ipv4.icmp_echo_ignore_all=1
net.core.bpf_jit_harden=1
kernel.kptr_restrict=1
vm.swappiness=60
fs.protected_hardlinks=1
fs.protected_symlinks=1
EOF
fi
sysctl -p >/dev/null 2>&1 || true
check_error "Failed to apply sysctl settings"

# Basic Firewall
status "Configuring iptables firewall"
iptables -P INPUT ACCEPT 2>/dev/null || true
iptables -F 2>/dev/null || true
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p udp --dport 51820 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -P INPUT DROP
# Persist rules (try both Debian and RHEL styles)
if command -v netfilter-persistent &>/dev/null; then
  netfilter-persistent save >/dev/null 2>&1 || true
elif command -v iptables-save &>/dev/null; then
  mkdir -p /etc/iptables
  iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
fi
check_error "Failed to configure iptables firewall"

status "Firewall and kernel hardening complete"