#!/bin/bash
# Helper functions for the GhostTunnel deployment scripts (generalized for nosrat)

# Status display function
status() {
  echo -e "\n\033[1;32m>>> $1\033[0m"
}

# Error checking function
# Usage: some_command; check_error "Failed to do something"
check_error() {
  if [ $? -ne 0 ]; then
    echo -e "\n\033[1;31mERROR: $1\033[0m"
    exit 1
  fi
}

# Detect OS package manager (apt vs dnf)
# Sets PKG_MGR env var
detect_pkg_mgr() {
  if command -v apt-get &>/dev/null; then
    PKG_MGR="apt"
  elif command -v dnf &>/dev/null; then
    PKG_MGR="dnf"
  elif command -v yum &>/dev/null; then
    PKG_MGR="yum"
  else
    echo "ERROR: no supported package manager found (apt/dnf/yum)" >&2
    exit 1
  fi
  export PKG_MGR
}

# Install packages using detected package manager
# Usage: pkg_install <pkg1> <pkg2> ...
pkg_install() {
  detect_pkg_mgr
  case "$PKG_MGR" in
    apt)
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"
      ;;
    dnf|yum)
      $PKG_MGR install -y "$@"
      ;;
  esac
}