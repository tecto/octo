#!/usr/bin/env bash
#
# OCTO Upgrade
# Upgrades OCTO while preserving configuration
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")"
OCTO_HOME="${OCTO_HOME:-$HOME/.octo}"
OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"

# New version (should be sourced from project or passed in)
NEW_VERSION="${OCTO_VERSION:-1.1.0}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            echo "Usage: octo upgrade [options]"
            echo ""
            echo "Upgrades OCTO to the latest version while preserving your configuration."
            echo ""
            echo "Options:"
            echo "  --help, -h     Show this help message"
            echo ""
            echo "This command will:"
            echo "  - Back up your current config.json"
            echo "  - Update plugin files"
            echo "  - Update version field"
            echo "  - Preserve all your settings"
            echo "  - Restart services if running"
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
    echo "Run 'octo install' first."
    exit 1
fi

echo -e "${BOLD}Upgrading OCTO...${NC}"
echo ""

# Get current version
CURRENT_VERSION=$(jq -r '.version // "unknown"' "$OCTO_HOME/config.json" 2>/dev/null || echo "unknown")
echo "Current version: $CURRENT_VERSION"
echo "New version: $NEW_VERSION"
echo ""

# Back up current config
BACKUP_FILE="$OCTO_HOME/config.json.backup"
cp "$OCTO_HOME/config.json" "$BACKUP_FILE"
log_ok "Backed up config to $BACKUP_FILE"

# Check if services are running
RESTART_SENTINEL=false
RESTART_WATCHDOG=false

if [ -f "$OCTO_HOME/sentinel.pid" ]; then
    PID=$(cat "$OCTO_HOME/sentinel.pid")
    if kill -0 "$PID" 2>/dev/null; then
        RESTART_SENTINEL=true
        echo "Stopping sentinel..."
        kill "$PID" 2>/dev/null || true
        sleep 1
    fi
fi

if [ -f "$OCTO_HOME/watchdog.pid" ]; then
    PID=$(cat "$OCTO_HOME/watchdog.pid")
    if kill -0 "$PID" 2>/dev/null; then
        RESTART_WATCHDOG=true
        echo "Stopping watchdog..."
        kill "$PID" 2>/dev/null || true
        sleep 1
    fi
fi

# Update version in config
jq --arg v "$NEW_VERSION" '.version = $v' "$OCTO_HOME/config.json" > "$OCTO_HOME/config.json.tmp"
mv "$OCTO_HOME/config.json.tmp" "$OCTO_HOME/config.json"
log_ok "Updated version to $NEW_VERSION"

# Update plugin files
PLUGIN_DIR="$OPENCLAW_HOME/plugins/token-optimizer"
if [ -d "$LIB_DIR/plugins/token-optimizer" ]; then
    mkdir -p "$PLUGIN_DIR"
    cp -r "$LIB_DIR/plugins/token-optimizer/"* "$PLUGIN_DIR/"
    log_ok "Updated plugin files"
else
    log_warn "Plugin source not found, skipping plugin update"
fi

# Merge any new default settings (if needed)
# This would be where we add new config fields from newer versions
# For now, we just preserve everything

# Restart services if they were running
if [ "$RESTART_SENTINEL" = true ]; then
    echo "Restarting sentinel..."
    if [ -f "$LIB_DIR/watchdog/bloat-sentinel.sh" ]; then
        bash "$LIB_DIR/watchdog/bloat-sentinel.sh" daemon 2>/dev/null &
        log_ok "Restarted sentinel"
    fi
fi

if [ "$RESTART_WATCHDOG" = true ]; then
    echo "Restarting watchdog..."
    if [ -f "$LIB_DIR/watchdog/openclaw-watchdog.sh" ]; then
        bash "$LIB_DIR/watchdog/openclaw-watchdog.sh" daemon 2>/dev/null &
        log_ok "Restarted watchdog"
    fi
fi

echo ""
echo -e "${GREEN}OCTO upgraded successfully!${NC}"
echo ""
echo "Your configuration has been preserved."
echo "Backup available at: $BACKUP_FILE"
