#!/usr/bin/env bash
#
# OCTO Uninstall
# Removes OCTO installation
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")"
OCTO_HOME="${OCTO_HOME:-$HOME/.octo}"
OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"

# Command line flags
FORCE=false
PURGE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force|-f)
            FORCE=true
            shift
            ;;
        --purge)
            PURGE=true
            shift
            ;;
        --help|-h)
            echo "Usage: octo uninstall [options]"
            echo ""
            echo "Options:"
            echo "  --force, -f    Skip confirmation prompt"
            echo "  --purge        Remove all data including costs history"
            echo "  --help, -h     Show this help message"
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

log_ok() {
    echo -e "  ${GREEN}✓${NC} $1"
}

log_warn() {
    echo -e "  ${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "  ${RED}✗${NC} $1"
}

# Check if OCTO is installed
if [ ! -f "$OCTO_HOME/config.json" ]; then
    echo -e "${RED}Error:${NC} OCTO is not installed"
    echo "Nothing to uninstall."
    exit 1
fi

# Confirmation prompt
if [ "$FORCE" != true ]; then
    echo -e "${YELLOW}Warning:${NC} This will remove OCTO installation."
    if [ "$PURGE" = true ]; then
        echo -e "${RED}PURGE MODE:${NC} All data including cost history will be deleted!"
    else
        echo "Cost history will be preserved."
    fi
    echo ""
    read -p "Are you sure you want to continue? [y/N] " -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Uninstall cancelled."
        exit 0
    fi
fi

echo -e "${BOLD}Uninstalling OCTO...${NC}"
echo ""

# Stop running services
if [ -f "$OCTO_HOME/sentinel.pid" ]; then
    PID=$(cat "$OCTO_HOME/sentinel.pid")
    if kill -0 "$PID" 2>/dev/null; then
        echo "Stopping bloat sentinel..."
        kill "$PID" 2>/dev/null || true
        log_ok "Stopped sentinel (PID: $PID)"
    fi
    rm -f "$OCTO_HOME/sentinel.pid"
fi

if [ -f "$OCTO_HOME/watchdog.pid" ]; then
    PID=$(cat "$OCTO_HOME/watchdog.pid")
    if kill -0 "$PID" 2>/dev/null; then
        echo "Stopping watchdog..."
        kill "$PID" 2>/dev/null || true
        log_ok "Stopped watchdog (PID: $PID)"
    fi
    rm -f "$OCTO_HOME/watchdog.pid"
fi

# Remove OCTO config
if [ -f "$OCTO_HOME/config.json" ]; then
    rm -f "$OCTO_HOME/config.json"
    log_ok "Removed config.json"
fi

# Remove token-optimizer plugin from OpenClaw
PLUGIN_DIR="$OPENCLAW_HOME/plugins/token-optimizer"
if [ -d "$PLUGIN_DIR" ]; then
    rm -rf "$PLUGIN_DIR"
    log_ok "Removed token-optimizer plugin"
fi

# Remove logs
if [ -d "$OCTO_HOME/logs" ]; then
    rm -rf "$OCTO_HOME/logs"
    log_ok "Removed logs directory"
fi

# Remove metrics
if [ -d "$OCTO_HOME/metrics" ]; then
    rm -rf "$OCTO_HOME/metrics"
    log_ok "Removed metrics directory"
fi

# Handle costs data
if [ "$PURGE" = true ]; then
    if [ -d "$OCTO_HOME/costs" ]; then
        rm -rf "$OCTO_HOME/costs"
        log_ok "Removed costs history (purge mode)"
    fi

    # Remove OCTO_HOME directory entirely
    if [ -d "$OCTO_HOME" ]; then
        rmdir "$OCTO_HOME" 2>/dev/null || true
        log_ok "Removed $OCTO_HOME directory"
    fi
else
    if [ -d "$OCTO_HOME/costs" ]; then
        log_warn "Preserved costs history at $OCTO_HOME/costs"
        echo "       Use --purge to remove all data"
    fi
fi

echo ""
echo -e "${GREEN}OCTO uninstalled successfully.${NC}"
echo ""
echo "To reinstall, run: octo install"
