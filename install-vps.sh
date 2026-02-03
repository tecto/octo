#!/usr/bin/env bash
#
# OCTO - OpenClaw Token Optimizer
# VPS Quick Installer (Non-Interactive)
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/trinsiklabs/octo/main/install-vps.sh | bash
#
# Options (via environment variables):
#   OPENCLAW_HOME    - Path to OpenClaw installation (default: ~/.openclaw)
#   OCTO_AUTOSTART   - Start services after install (default: true)
#   OCTO_VERSION     - Version to install (default: latest)
#

set -euo pipefail

# Configuration
OCTO_VERSION="${OCTO_VERSION:-latest}"
OCTO_REPO="${OCTO_REPO:-trinsiklabs/octo}"
INSTALL_DIR="${OCTO_INSTALL_DIR:-$HOME/.local/share/octo}"
BIN_DIR="${OCTO_BIN_DIR:-$HOME/.local/bin}"
OCTO_AUTOSTART="${OCTO_AUTOSTART:-true}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log() { echo -e "${GREEN}[OCTO]${NC} $1"; }
warn() { echo -e "${YELLOW}[OCTO]${NC} $1"; }
error() { echo -e "${RED}[OCTO]${NC} $1" >&2; }

echo -e "${CYAN}"
cat << 'EOF'
   ____   _____ _______ ____
  / __ \ / ____|__   __/ __ \
 | |  | | |       | | | |  | |
 | |  | | |       | | | |  | |
 | |__| | |____   | | | |__| |
  \____/ \_____|  |_|  \____/

  OpenClaw Token Optimizer
  VPS Quick Installer
EOF
echo -e "${NC}"

# Check prerequisites
log "Checking prerequisites..."

MISSING_DEPS=()

if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
    MISSING_DEPS+=("curl or wget")
fi

if ! command -v tar &>/dev/null; then
    MISSING_DEPS+=("tar")
fi

if ! command -v python3 &>/dev/null; then
    MISSING_DEPS+=("python3")
fi

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    error "Missing required dependencies: ${MISSING_DEPS[*]}"
    error "Install with: apt-get install -y curl tar python3 jq"
    exit 1
fi

if ! command -v jq &>/dev/null; then
    warn "jq not found. Installing..."
    if command -v apt-get &>/dev/null; then
        sudo apt-get update -qq && sudo apt-get install -y -qq jq
    elif command -v yum &>/dev/null; then
        sudo yum install -y jq
    elif command -v brew &>/dev/null; then
        brew install jq
    else
        warn "Could not auto-install jq. Some features may be limited."
    fi
fi

log "All prerequisites met"

# Auto-detect OpenClaw
OPENCLAW_HOME="${OPENCLAW_HOME:-}"

if [ -z "$OPENCLAW_HOME" ]; then
    # Try common locations
    for candidate in "$HOME/.openclaw" "/root/.openclaw" "/home/openclaw/.openclaw"; do
        if [ -d "$candidate" ]; then
            OPENCLAW_HOME="$candidate"
            break
        fi
    done
fi

if [ -z "$OPENCLAW_HOME" ] || [ ! -d "$OPENCLAW_HOME" ]; then
    warn "OpenClaw not found. Set OPENCLAW_HOME environment variable."
    warn "OCTO will be installed but services won't start until OpenClaw is configured."
    OPENCLAW_HOME="$HOME/.openclaw"
else
    log "OpenClaw found at $OPENCLAW_HOME"
fi

export OPENCLAW_HOME

# Create directories
log "Installing OCTO..."

mkdir -p "$INSTALL_DIR"
mkdir -p "$BIN_DIR"
mkdir -p "$HOME/.octo"/{logs,costs,metrics}

# Download
if [ "$OCTO_VERSION" = "latest" ] || [ "$OCTO_VERSION" = "main" ]; then
    log "Downloading latest version from $OCTO_REPO..."
    DOWNLOAD_URL="https://github.com/$OCTO_REPO/archive/refs/heads/main.tar.gz"
else
    log "Downloading version $OCTO_VERSION..."
    DOWNLOAD_URL="https://github.com/$OCTO_REPO/archive/refs/tags/$OCTO_VERSION.tar.gz"
fi

if command -v curl &>/dev/null; then
    curl -fsSL "$DOWNLOAD_URL" | tar xz -C "$INSTALL_DIR" --strip-components=1
else
    wget -qO- "$DOWNLOAD_URL" | tar xz -C "$INSTALL_DIR" --strip-components=1
fi

log "Downloaded OCTO"

# Make scripts executable
chmod +x "$INSTALL_DIR/bin/octo"
find "$INSTALL_DIR/lib" -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true

# Create symlink
ln -sf "$INSTALL_DIR/bin/octo" "$BIN_DIR/octo"

log "Installed OCTO to $INSTALL_DIR"
log "Linked octo command to $BIN_DIR/octo"

# Add to PATH if needed
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    export PATH="$PATH:$BIN_DIR"

    # Persist to shell profile
    PROFILE_FILE=""
    if [ -f "$HOME/.bashrc" ]; then
        PROFILE_FILE="$HOME/.bashrc"
    elif [ -f "$HOME/.bash_profile" ]; then
        PROFILE_FILE="$HOME/.bash_profile"
    elif [ -f "$HOME/.zshrc" ]; then
        PROFILE_FILE="$HOME/.zshrc"
    elif [ -f "$HOME/.profile" ]; then
        PROFILE_FILE="$HOME/.profile"
    fi

    if [ -n "$PROFILE_FILE" ]; then
        if ! grep -q "$BIN_DIR" "$PROFILE_FILE" 2>/dev/null; then
            echo "" >> "$PROFILE_FILE"
            echo "# OCTO" >> "$PROFILE_FILE"
            echo "export PATH=\"\$PATH:$BIN_DIR\"" >> "$PROFILE_FILE"
            log "Added $BIN_DIR to PATH in $PROFILE_FILE"
        fi
    fi
fi

# Create default config if not exists
CONFIG_FILE="$HOME/.octo/config.json"
if [ ! -f "$CONFIG_FILE" ]; then
    cp "$INSTALL_DIR/lib/config/default_config.json" "$CONFIG_FILE"
    log "Created default config at $CONFIG_FILE"
fi

# Store OPENCLAW_HOME in config
if [ -f "$CONFIG_FILE" ] && command -v jq &>/dev/null; then
    jq --arg home "$OPENCLAW_HOME" '.openclawHome = $home' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
fi

# Summary
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  OCTO Installation Complete!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo "  Installation:  $INSTALL_DIR"
echo "  Binary:        $BIN_DIR/octo"
echo "  Config:        $HOME/.octo/config.json"
echo "  OpenClaw:      $OPENCLAW_HOME"
echo ""

# Auto-start services if requested and OpenClaw exists
if [ "$OCTO_AUTOSTART" = "true" ] && [ -d "$OPENCLAW_HOME" ]; then
    log "Starting OCTO services..."

    # Start sentinel (bloat detection)
    if "$BIN_DIR/octo" sentinel start 2>/dev/null; then
        log "Bloat sentinel started"
    else
        warn "Could not start sentinel (OpenClaw may not be running)"
    fi

    # Start watchdog (health monitoring)
    if "$BIN_DIR/octo" watchdog start 2>/dev/null; then
        log "Health watchdog started"
    else
        warn "Could not start watchdog (OpenClaw may not be running)"
    fi

    echo ""
    "$BIN_DIR/octo" status 2>/dev/null || true
else
    echo -e "  ${BOLD}Next steps:${NC}"
    echo "    1. Ensure OpenClaw is installed and OPENCLAW_HOME is set"
    echo "    2. Run 'octo status' to check current state"
    echo "    3. Run 'octo sentinel start' to enable bloat detection"
    echo "    4. Run 'octo watchdog start' to enable health monitoring"
fi

echo ""
echo -e "  ${BOLD}Commands:${NC}"
echo "    octo status     - Check optimization status"
echo "    octo analyze    - Deep token analysis"
echo "    octo doctor     - Health diagnostics"
echo "    octo --help     - All commands"
echo ""

# Onelist upsell for maximum savings
echo -e "${YELLOW}════════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  Want ${BOLD}90-95%${NC}${YELLOW} MORE savings? Add Onelist semantic memory${NC}"
echo -e "${YELLOW}════════════════════════════════════════════════════════════════${NC}"
echo ""

# Check system resources for Onelist
check_resources() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        RAM_GB=$(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 ))
        CPU_CORES=$(sysctl -n hw.ncpu)
    else
        RAM_GB=$(( $(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 / 1024 ))
        CPU_CORES=$(nproc 2>/dev/null || echo 2)
    fi
    DISK_GB=$(df -BG "$HOME" 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G' || echo "50")
    echo "$RAM_GB $CPU_CORES $DISK_GB"
}

read -r RAM_GB CPU_CORES DISK_GB <<< "$(check_resources)"

RAM_OK=$([[ "$RAM_GB" -ge 4 ]] && echo "yes" || echo "no")
CPU_OK=$([[ "$CPU_CORES" -ge 2 ]] && echo "yes" || echo "no")
DISK_OK=$([[ "${DISK_GB:-0}" -ge 10 ]] && echo "yes" || echo "no")

echo "  System resources:"
if [ "$RAM_OK" = "yes" ]; then
    echo -e "    ${GREEN}✓${NC} RAM:  ${RAM_GB}GB (4GB required)"
else
    echo -e "    ${RED}✗${NC} RAM:  ${RAM_GB}GB (4GB required)"
fi
if [ "$CPU_OK" = "yes" ]; then
    echo -e "    ${GREEN}✓${NC} CPU:  ${CPU_CORES} cores (2 required)"
else
    echo -e "    ${RED}✗${NC} CPU:  ${CPU_CORES} cores (2 required)"
fi
if [ "$DISK_OK" = "yes" ]; then
    echo -e "    ${GREEN}✓${NC} Disk: ${DISK_GB}GB (10GB required)"
else
    echo -e "    ${RED}✗${NC} Disk: ${DISK_GB}GB (10GB required)"
fi
echo ""

# Check if Onelist is already installed
ONELIST_INSTALLED="false"
if [ -f "$HOME/.octo/config.json" ] && command -v jq &>/dev/null; then
    ONELIST_INSTALLED=$(jq -r '.onelist.installed // false' "$HOME/.octo/config.json" 2>/dev/null || echo "false")
fi

# Auto-install Onelist if requested and resources available
OCTO_INSTALL_ONELIST="${OCTO_INSTALL_ONELIST:-false}"

if [ "$ONELIST_INSTALLED" = "true" ]; then
    log "Onelist already installed - skipping"
    echo "  Run 'octo onelist --status' to check status"
elif [ "$RAM_OK" = "yes" ] && [ "$CPU_OK" = "yes" ] && [ "$DISK_OK" = "yes" ]; then
    if [ "$OCTO_INSTALL_ONELIST" = "true" ]; then
        log "Installing Onelist for maximum savings..."
        "$BIN_DIR/octo" onelist --method=docker 2>/dev/null || warn "Onelist installation requires Docker. Run 'octo onelist' manually."
    else
        echo "  To install Onelist and get 90-95% additional savings:"
        echo ""
        echo -e "    ${CYAN}octo onelist --method=docker${NC}"
        echo ""
        echo "  Or re-run this installer with:"
        echo ""
        echo -e "    ${CYAN}OCTO_INSTALL_ONELIST=true curl -fsSL ... | bash${NC}"
    fi
else
    echo -e "  ${YELLOW}System does not meet Onelist requirements.${NC}"
    echo -e "  ${YELLOW}OCTO standalone optimizations are still active (60-75% savings).${NC}"
fi

echo ""
