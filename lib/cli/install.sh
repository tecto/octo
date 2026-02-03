#!/usr/bin/env bash
#
# OCTO Install Wizard
# Interactive setup for OpenClaw Token Optimizer
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")"
OCTO_HOME="${OCTO_HOME:-$HOME/.octo}"
OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"
OCTO_PORT="${OCTO_PORT:-6286}"

# Command line flags
CHECK_ONLY=false
FORCE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --check-only)
            CHECK_ONLY=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# Check if OCTO is already installed
is_octo_installed() {
    [ -f "$OCTO_HOME/config.json" ]
}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Configuration state
ENABLE_CACHING=true
ENABLE_TIERING=true
ENABLE_MONITORING=true
ENABLE_BLOAT_DETECTION=true
ENABLE_COST_TRACKING=true
CUSTOM_PORT=""

log_step() {
    local step="$1"
    local total="$2"
    local message="$3"
    echo -e "\n${CYAN}[$step/$total]${NC} ${BOLD}$message${NC}"
}

log_ok() {
    echo -e "    ${GREEN}✓${NC} $1"
}

log_info() {
    echo -e "    ${BLUE}•${NC} $1"
}

log_warn() {
    echo -e "    ${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "    ${RED}✗${NC} $1"
}

prompt_yn() {
    local prompt="$1"
    local default="${2:-Y}"
    local result

    if [ "$default" = "Y" ]; then
        echo -en "    $prompt ${DIM}[Y/n]${NC} "
    else
        echo -en "    $prompt ${DIM}[y/N]${NC} "
    fi

    read -r result
    result="${result:-$default}"

    [[ "$result" =~ ^[Yy] ]]
}

prompt_port() {
    local default="$1"
    local result

    echo -en "    Enter port ${DIM}[$default]${NC}: "
    read -r result
    result="${result:-$default}"
    echo "$result"
}

check_port_available() {
    local port="$1"
    if command -v lsof &>/dev/null; then
        if lsof -i ":$port" &>/dev/null; then
            return 1
        fi
    elif command -v ss &>/dev/null; then
        if ss -tuln | grep -q ":$port "; then
            return 1
        fi
    elif command -v netstat &>/dev/null; then
        if netstat -tuln | grep -q ":$port "; then
            return 1
        fi
    fi
    return 0
}

check_resources() {
    # Get RAM in GB
    if [[ "$OSTYPE" == "darwin"* ]]; then
        RAM_GB=$(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 ))
        CPU_CORES=$(sysctl -n hw.ncpu)
    else
        RAM_GB=$(( $(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 / 1024 ))
        CPU_CORES=$(nproc)
    fi

    # Get available disk space in GB
    DISK_GB=$(df -BG "$HOME" 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G' || echo "50")

    echo "$RAM_GB $CPU_CORES $DISK_GB"
}

show_banner() {
    clear
    echo -e "${CYAN}"
    cat << 'EOF'
   ____   _____ _______ ____
  / __ \ / ____|__   __/ __ \
 | |  | | |       | | | |  | |
 | |  | | |       | | | |  | |
 | |__| | |____   | | | |__| |
  \____/ \_____|  |_|  \____/

  OpenClaw Token Optimizer
  Installation Wizard
EOF
    echo -e "${NC}"
}

# Main installation flow
main() {
    # Check for existing installation FIRST (before banner)
    if is_octo_installed && [ "$FORCE" != true ]; then
        if [ "$CHECK_ONLY" = true ]; then
            echo "OCTO is already installed at $OCTO_HOME"
            echo ""
            echo "Options:"
            echo "  octo uninstall    - Remove OCTO completely"
            echo "  octo reinstall    - Clean reinstall (removes config)"
            echo "  octo upgrade      - Upgrade while preserving config"
            exit 1
        fi

        echo -e "${RED}OCTO is already installed${NC} at $OCTO_HOME"
        echo ""
        echo "Options:"
        echo "  octo uninstall    - Remove OCTO completely"
        echo "  octo reinstall    - Clean reinstall (removes config)"
        echo "  octo upgrade      - Upgrade while preserving config"
        echo ""
        echo "Or use 'octo install --force' to overwrite existing installation."
        exit 1
    fi

    # Check-only mode exits cleanly if not installed
    if [ "$CHECK_ONLY" = true ]; then
        echo "OCTO is not installed. Ready for fresh installation."
        exit 0
    fi

    show_banner

    echo -e "${BOLD}This wizard will configure OCTO to optimize your OpenClaw costs.${NC}"
    echo -e "${DIM}Estimated time: 2-3 minutes${NC}"
    echo ""

    # Step 1: Detect OpenClaw
    log_step 1 7 "Detecting OpenClaw installation..."

    if [ -d "$OPENCLAW_HOME" ]; then
        log_ok "Found OpenClaw at $OPENCLAW_HOME"

        # Check for existing sessions
        SESSION_COUNT=$(find "$OPENCLAW_HOME/agents" -name "*.jsonl" 2>/dev/null | wc -l | tr -d ' ')
        if [ "$SESSION_COUNT" -gt 0 ]; then
            log_info "Found $SESSION_COUNT existing session files"
        fi

        # Check for existing config
        if [ -f "$OPENCLAW_HOME/openclaw.json" ]; then
            log_ok "Found OpenClaw configuration"
        fi
    else
        log_error "OpenClaw not found at $OPENCLAW_HOME"
        echo ""
        echo "Please install OpenClaw first or set OPENCLAW_HOME environment variable."
        exit 1
    fi

    # Step 2: Analyze current configuration
    log_step 2 7 "Analyzing current configuration..."

    EXISTING_PLUGINS=""
    if [ -f "$OPENCLAW_HOME/openclaw.json" ]; then
        EXISTING_PLUGINS=$(jq -r '.plugins // [] | .[]' "$OPENCLAW_HOME/openclaw.json" 2>/dev/null || echo "")
    fi

    if [ -n "$EXISTING_PLUGINS" ]; then
        log_info "Existing plugins: $EXISTING_PLUGINS"
    else
        log_info "No plugins currently configured"
    fi

    # Step 3: Prompt Caching
    log_step 3 7 "Configuring prompt caching..."
    log_info "Enables Anthropic cache headers for repeated context"
    log_info "Estimated savings: ${GREEN}25-40%${NC} on cached portions"

    if prompt_yn "Enable prompt caching?"; then
        ENABLE_CACHING=true
        log_ok "Prompt caching enabled"
    else
        ENABLE_CACHING=false
        log_info "Prompt caching disabled"
    fi

    # Step 4: Model Tiering
    log_step 4 7 "Setting up model tiering..."
    log_info "Routes simple tasks to Haiku, complex ones to Sonnet/Opus"
    log_info "Estimated savings: ${GREEN}35-50%${NC} on tierable requests"

    if prompt_yn "Enable model tiering?"; then
        ENABLE_TIERING=true
        log_ok "Model tiering enabled"
    else
        ENABLE_TIERING=false
        log_info "Model tiering disabled"
    fi

    # Step 5: Session Monitoring
    log_step 5 7 "Configuring session monitoring..."
    log_info "Tracks context window utilization"
    log_info "Alerts at 70% (warning) and 90% (critical)"

    if prompt_yn "Enable session monitoring?"; then
        ENABLE_MONITORING=true
        log_ok "Session monitoring enabled"
    else
        ENABLE_MONITORING=false
        log_info "Session monitoring disabled"
    fi

    # Step 6: Bloat Detection
    log_step 6 7 "Setting up bloat detection..."
    log_info "Detects and stops injection feedback loops"
    log_info "Prevents runaway costs from context spirals"

    if prompt_yn "Enable bloat detection?"; then
        ENABLE_BLOAT_DETECTION=true
        log_ok "Bloat detection enabled"
    else
        ENABLE_BLOAT_DETECTION=false
        log_info "Bloat detection disabled"
    fi

    # Step 7: Dashboard Port
    log_step 7 7 "Configuring web dashboard..."

    # Check default port
    if check_port_available "$OCTO_PORT"; then
        log_ok "Default port $OCTO_PORT (OCTO in T9) is available"
        CUSTOM_PORT="$OCTO_PORT"
    else
        log_warn "Default port $OCTO_PORT is in use"
        while true; do
            CUSTOM_PORT=$(prompt_port "$OCTO_PORT")
            if check_port_available "$CUSTOM_PORT"; then
                log_ok "Port $CUSTOM_PORT is available"
                break
            else
                log_error "Port $CUSTOM_PORT is in use, please choose another"
            fi
        done
    fi

    # Generate configuration
    echo ""
    echo -e "${BOLD}Generating configuration...${NC}"

    mkdir -p "$OCTO_HOME"

    cat > "$OCTO_HOME/config.json" << EOF
{
  "version": "1.0.0",
  "installedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",

  "optimization": {
    "promptCaching": {
      "enabled": $ENABLE_CACHING,
      "cacheSystemPrompt": true,
      "cacheTools": true,
      "cacheHistoryOlderThan": 5
    },
    "modelTiering": {
      "enabled": $ENABLE_TIERING,
      "defaultModel": "sonnet"
    }
  },

  "monitoring": {
    "sessionMonitor": {
      "enabled": $ENABLE_MONITORING,
      "warningThreshold": 0.70,
      "criticalThreshold": 0.90
    },
    "bloatSentinel": {
      "enabled": $ENABLE_BLOAT_DETECTION,
      "autoIntervene": true
    },
    "watchdog": {
      "enabled": true
    }
  },

  "costTracking": {
    "enabled": true
  },

  "dashboard": {
    "enabled": true,
    "port": $CUSTOM_PORT,
    "host": "localhost"
  },

  "onelist": {
    "installed": false
  }
}
EOF

    log_ok "Configuration saved to $OCTO_HOME/config.json"

    # Install OpenClaw plugin
    echo ""
    echo -e "${BOLD}Installing OpenClaw plugin...${NC}"

    PLUGIN_DIR="$OPENCLAW_HOME/plugins/token-optimizer"
    mkdir -p "$PLUGIN_DIR"

    # Copy plugin files
    if [ -d "$LIB_DIR/plugins/token-optimizer" ]; then
        cp -r "$LIB_DIR/plugins/token-optimizer/"* "$PLUGIN_DIR/"
        log_ok "Plugin installed to $PLUGIN_DIR"
    else
        log_warn "Plugin source not found, will be installed on first run"
    fi

    # Calculate estimated savings
    SAVINGS_LOW=0
    SAVINGS_HIGH=0

    if [ "$ENABLE_CACHING" = true ]; then
        SAVINGS_LOW=$((SAVINGS_LOW + 25))
        SAVINGS_HIGH=$((SAVINGS_HIGH + 40))
    fi

    if [ "$ENABLE_TIERING" = true ]; then
        SAVINGS_LOW=$((SAVINGS_LOW + 20))
        SAVINGS_HIGH=$((SAVINGS_HIGH + 35))
    fi

    if [ "$ENABLE_BLOAT_DETECTION" = true ]; then
        SAVINGS_LOW=$((SAVINGS_LOW + 5))
        SAVINGS_HIGH=$((SAVINGS_HIGH + 15))
    fi

    # Cap at reasonable max
    [ "$SAVINGS_HIGH" -gt 75 ] && SAVINGS_HIGH=75
    [ "$SAVINGS_LOW" -gt 60 ] && SAVINGS_LOW=60

    # Summary
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  Setup Complete! Estimated savings: ${BOLD}${SAVINGS_LOW}-${SAVINGS_HIGH}%${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${BOLD}Dashboard:${NC} http://localhost:${CUSTOM_PORT}"
    echo ""
    echo -e "  ${BOLD}Quick commands:${NC}"
    echo "    octo status     - View current status"
    echo "    octo doctor     - Run health check"
    echo "    octo analyze    - Analyze usage patterns"
    echo ""

    # Onelist upsell
    echo -e "${YELLOW}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  💡 Want ${BOLD}90-95%${NC}${YELLOW} MORE savings? Install Onelist-local${NC}"
    echo -e "${YELLOW}════════════════════════════════════════════════════════════════${NC}"
    echo ""

    # Check system resources
    read -r RAM_GB CPU_CORES DISK_GB <<< "$(check_resources)"

    RAM_OK=$([[ "$RAM_GB" -ge 4 ]] && echo "✓" || echo "✗")
    CPU_OK=$([[ "$CPU_CORES" -ge 2 ]] && echo "✓" || echo "✗")
    DISK_OK=$([[ "$DISK_GB" -ge 10 ]] && echo "✓" || echo "✗")

    echo "  Your system resources:"
    echo -e "    RAM:  ${RAM_GB}GB $([[ "$RAM_OK" = "✓" ]] && echo "${GREEN}$RAM_OK${NC}" || echo "${RED}$RAM_OK${NC}") (4GB required)"
    echo -e "    CPU:  ${CPU_CORES} cores $([[ "$CPU_OK" = "✓" ]] && echo "${GREEN}$CPU_OK${NC}" || echo "${RED}$CPU_OK${NC}") (2 required)"
    echo -e "    Disk: ${DISK_GB}GB $([[ "$DISK_OK" = "✓" ]] && echo "${GREEN}$DISK_OK${NC}" || echo "${RED}$DISK_OK${NC}") (10GB required)"
    echo ""

    if [[ "$RAM_OK" = "✓" && "$CPU_OK" = "✓" && "$DISK_OK" = "✓" ]]; then
        if prompt_yn "Install Onelist-local now?" "N"; then
            echo ""
            source "$LIB_DIR/cli/onelist.sh"
        else
            echo ""
            echo "  Run 'octo onelist' anytime to install Onelist."
        fi
    else
        echo -e "  ${DIM}System does not meet Onelist requirements.${NC}"
        echo -e "  ${DIM}OCTO standalone optimizations are still active.${NC}"
    fi

    echo ""

    # Start services
    if [ "$ENABLE_BLOAT_DETECTION" = true ]; then
        echo -e "${BOLD}Starting bloat sentinel...${NC}"
        if [ -f "$LIB_DIR/watchdog/bloat-sentinel.sh" ]; then
            bash "$LIB_DIR/watchdog/bloat-sentinel.sh" daemon 2>/dev/null || log_warn "Could not start sentinel (may need manual start)"
        fi
    fi

    echo ""
    echo -e "${GREEN}OCTO installation complete!${NC}"
    echo ""
}

main "$@"
