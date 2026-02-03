#!/usr/bin/env bash
#
# OCTO - OpenClaw Token Optimizer
# One-line installer
#
# Usage: curl -fsSL https://raw.githubusercontent.com/trinsiklabs/octo/main/install.sh | bash
#
# For non-interactive VPS install, use install-vps.sh instead.
#

set -euo pipefail

# Configuration
OCTO_VERSION="${OCTO_VERSION:-latest}"
OCTO_REPO="${OCTO_REPO:-trinsiklabs/octo}"
INSTALL_DIR="${OCTO_INSTALL_DIR:-$HOME/.local/share/octo}"
BIN_DIR="${OCTO_BIN_DIR:-$HOME/.local/bin}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}"
cat << 'EOF'
   ____   _____ _______ ____
  / __ \ / ____|__   __/ __ \
 | |  | | |       | | | |  | |
 | |  | | |       | | | |  | |
 | |__| | |____   | | | |__| |
  \____/ \_____|  |_|  \____/

  OpenClaw Token Optimizer
  Installer
EOF
echo -e "${NC}"

# Check prerequisites
echo -e "${BOLD}Checking prerequisites...${NC}"

# Check for required commands
MISSING_DEPS=()

if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
    MISSING_DEPS+=("curl or wget")
fi

if ! command -v tar &>/dev/null; then
    MISSING_DEPS+=("tar")
fi

if ! command -v jq &>/dev/null; then
    echo -e "${YELLOW}Warning:${NC} jq not found. Some features may be limited."
    echo "Install jq for full functionality: https://stedolan.github.io/jq/download/"
fi

if ! command -v python3 &>/dev/null; then
    MISSING_DEPS+=("python3")
fi

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    echo -e "${RED}Error:${NC} Missing required dependencies: ${MISSING_DEPS[*]}"
    exit 1
fi

echo -e "${GREEN}✓${NC} All prerequisites met"

# Check for OpenClaw
OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"
if [ ! -d "$OPENCLAW_HOME" ]; then
    echo -e "${YELLOW}Warning:${NC} OpenClaw not found at $OPENCLAW_HOME"
    echo "OCTO will be installed but cannot function without OpenClaw."
    echo ""
    if [ -t 0 ]; then
        # Interactive mode - ask user
        read -p "Continue anyway? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        # Non-interactive mode - abort
        echo -e "${RED}Error:${NC} OpenClaw required. Set OPENCLAW_HOME or install OpenClaw first."
        exit 1
    fi
else
    echo -e "${GREEN}✓${NC} OpenClaw found at $OPENCLAW_HOME"
fi

# Create directories
echo -e "\n${BOLD}Installing OCTO...${NC}"

mkdir -p "$INSTALL_DIR"
mkdir -p "$BIN_DIR"
mkdir -p "$HOME/.octo"/{logs,costs,metrics}

# Download or clone
if [ "$OCTO_VERSION" = "latest" ] || [ "$OCTO_VERSION" = "main" ]; then
    echo "Downloading latest version..."

    if command -v curl &>/dev/null; then
        curl -fsSL "https://github.com/$OCTO_REPO/archive/refs/heads/main.tar.gz" | tar xz -C "$INSTALL_DIR" --strip-components=1
    else
        wget -qO- "https://github.com/$OCTO_REPO/archive/refs/heads/main.tar.gz" | tar xz -C "$INSTALL_DIR" --strip-components=1
    fi
else
    echo "Downloading version $OCTO_VERSION..."

    if command -v curl &>/dev/null; then
        curl -fsSL "https://github.com/$OCTO_REPO/archive/refs/tags/$OCTO_VERSION.tar.gz" | tar xz -C "$INSTALL_DIR" --strip-components=1
    else
        wget -qO- "https://github.com/$OCTO_REPO/archive/refs/tags/$OCTO_VERSION.tar.gz" | tar xz -C "$INSTALL_DIR" --strip-components=1
    fi
fi

echo -e "${GREEN}✓${NC} Downloaded OCTO"

# Make scripts executable
chmod +x "$INSTALL_DIR/bin/octo"
chmod +x "$INSTALL_DIR/lib/cli/"*.sh 2>/dev/null || true
chmod +x "$INSTALL_DIR/lib/watchdog/"*.sh 2>/dev/null || true
chmod +x "$INSTALL_DIR/lib/integrations/onelist/"*.sh 2>/dev/null || true

# Create symlink
ln -sf "$INSTALL_DIR/bin/octo" "$BIN_DIR/octo"

echo -e "${GREEN}✓${NC} Installed OCTO to $INSTALL_DIR"
echo -e "${GREEN}✓${NC} Linked octo command to $BIN_DIR/octo"

# Check if bin dir is in PATH
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    echo ""
    echo -e "${YELLOW}Note:${NC} $BIN_DIR is not in your PATH"
    echo ""
    echo "Add this to your shell profile (~/.bashrc, ~/.zshrc, etc.):"
    echo ""
    echo "  export PATH=\"\$PATH:$BIN_DIR\""
    echo ""
    echo "Then restart your shell or run: source ~/.bashrc"
    echo ""

    # Try to detect shell and suggest
    SHELL_NAME=$(basename "$SHELL")
    case "$SHELL_NAME" in
        bash)
            echo "Detected bash. Run:"
            echo "  echo 'export PATH=\"\$PATH:$BIN_DIR\"' >> ~/.bashrc && source ~/.bashrc"
            ;;
        zsh)
            echo "Detected zsh. Run:"
            echo "  echo 'export PATH=\"\$PATH:$BIN_DIR\"' >> ~/.zshrc && source ~/.zshrc"
            ;;
    esac
fi

# Summary
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  OCTO Installation Complete!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo "  Installation directory: $INSTALL_DIR"
echo "  Binary:                 $BIN_DIR/octo"
echo "  Config directory:       $HOME/.octo"
echo ""
echo -e "  ${BOLD}Next steps:${NC}"
echo "    1. Run 'octo install' to configure optimizations"
echo "    2. Run 'octo status' to check current state"
echo "    3. Run 'octo --help' for all commands"
echo ""
echo -e "  ${BOLD}Dashboard:${NC} http://localhost:6286 (after setup)"
echo ""

# Offer to run install wizard (only in interactive mode)
if [ -t 0 ]; then
    echo -n "Run setup wizard now? [Y/n] "
    read -r REPLY
    REPLY="${REPLY:-Y}"

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        exec "$BIN_DIR/octo" install
    fi
else
    echo "Run 'octo install' to configure optimizations."
fi
