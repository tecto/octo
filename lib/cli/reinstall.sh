#!/usr/bin/env bash
#
# OCTO Reinstall
# Clean reinstall - uninstalls then installs fresh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")"
OCTO_HOME="${OCTO_HOME:-$HOME/.octo}"
OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"

# Command line flags
FORCE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force|-f)
            FORCE=true
            shift
            ;;
        --help|-h)
            echo "Usage: octo reinstall [options]"
            echo ""
            echo "Performs a clean reinstall of OCTO."
            echo "This removes the existing installation and runs a fresh install."
            echo ""
            echo "Options:"
            echo "  --force, -f    Skip confirmation prompt"
            echo "  --help, -h     Show this help message"
            echo ""
            echo "Note: This will NOT preserve your configuration."
            echo "Use 'octo upgrade' if you want to keep your settings."
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

# Check if OCTO is installed
if [ ! -f "$OCTO_HOME/config.json" ]; then
    echo -e "${RED}Error:${NC} OCTO is not installed"
    echo "Run 'octo install' for a fresh installation."
    exit 1
fi

# Warning and confirmation
if [ "$FORCE" != true ]; then
    echo -e "${YELLOW}Warning:${NC} Reinstall will remove your current OCTO configuration."
    echo ""
    echo "This process will:"
    echo "  1. Uninstall the current OCTO installation"
    echo "  2. Run a fresh install wizard"
    echo ""
    echo -e "${RED}Your custom settings will be lost.${NC}"
    echo "Use 'octo upgrade' instead if you want to preserve settings."
    echo ""
    read -p "Are you sure you want to continue? [y/N] " -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Reinstall cancelled."
        exit 0
    fi
fi

echo -e "${BOLD}Reinstalling OCTO...${NC}"
echo ""

# Step 1: Uninstall
echo "Step 1: Uninstalling current installation..."
source "$SCRIPT_DIR/uninstall.sh" --force

echo ""

# Step 2: Fresh install
echo "Step 2: Running fresh install..."
source "$SCRIPT_DIR/install.sh" --force

echo ""
echo -e "${GREEN}Reinstall complete!${NC}"
