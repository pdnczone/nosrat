#!/usr/bin/env bash
# nosrat — CLI wrapper that runs the interactive installer/manager
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SCRIPT="/usr/local/bin/nosrat-install.sh"

# Run the install script (which shows the interactive menu)
exec bash "$INSTALL_SCRIPT" "$@"
