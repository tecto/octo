#!/usr/bin/env bash
#
# OCTO Onelist Integration
# Detects running Onelist or offers to install onelist-local
#
# Detection layers (in order):
# 1. Process detection (beam.smp/elixir)
# 2. Docker container detection
# 3. Config/installation file detection
# 4. Systemd service check
#
# OCTO does NOT:
# - Install Docker containers
# - Set up PostgreSQL
# - Create databases
# - Create onelist-memory plugin (that's in onelist-local)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")"
OCTO_HOME="${OCTO_HOME:-$HOME/.octo}"
OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"

# Default configuration
ONELIST_PORT="${ONELIST_PORT:-4000}"
ONELIST_URL="${ONELIST_URL:-http://localhost:$ONELIST_PORT}"
ONELIST_LOCAL_INSTALLER="https://raw.githubusercontent.com/trinsiklabs/onelist-local/main/install.sh"

# Detection results
DETECTED_METHOD=""
DETECTED_PORT=""
DETECTED_INFO=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

show_help() {
    echo "Usage: octo onelist [options]"
    echo ""
    echo "Detect and connect to Onelist for maximum savings."
    echo ""
    echo "Options:"
    echo "  --url=URL        Onelist URL (default: http://localhost:4000)"
    echo "  --port=PORT      Onelist port (default: 4000)"
    echo "  --status         Show connection status"
    echo "  --disconnect     Disconnect from Onelist"
    echo "  --detect         Run detection and show results"
    echo "  -h, --help       Show this help"
    echo ""
    echo "Detection methods (checked in order):"
    echo "  1. Process detection (beam.smp/elixir processes)"
    echo "  2. Docker container detection"
    echo "  3. Config file detection (~/.onelist/)"
    echo "  4. Systemd service check"
    echo ""
    echo "Examples:"
    echo "  octo onelist                          # Detect or install"
    echo "  octo onelist --url=http://192.168.1.100:4000"
    echo "  octo onelist --status                 # Check connection"
    echo "  octo onelist --detect                 # Show detection results"
}

log_ok() {
    echo -e "  ${GREEN}✓${NC} $1"
}

log_info() {
    echo -e "  ${BLUE}•${NC} $1"
}

log_warn() {
    echo -e "  ${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "  ${RED}✗${NC} $1"
}

# Check if Onelist is responding at a given URL
check_onelist_health() {
    local url="${1:-$ONELIST_URL}"
    local health_url="${url}/api/health"

    if curl -s --connect-timeout 3 --max-time 5 "$health_url" >/dev/null 2>&1; then
        return 0
    fi

    # Try alternate health endpoint
    health_url="${url}/health"
    if curl -s --connect-timeout 3 --max-time 5 "$health_url" >/dev/null 2>&1; then
        return 0
    fi

    return 1
}

# Layer 1: Process detection
detect_process() {
    local pid=""
    local port=""

    # Check for BEAM process with onelist in path/args
    pid=$(pgrep -f "beam.smp.*onelist" 2>/dev/null | head -1) || true

    if [ -z "$pid" ]; then
        # Try broader Elixir/Phoenix detection
        pid=$(pgrep -f "beam.smp.*phx" 2>/dev/null | head -1) || true
    fi

    if [ -z "$pid" ]; then
        # Check for elixir process
        pid=$(pgrep -f "elixir.*onelist" 2>/dev/null | head -1) || true
    fi

    if [ -n "$pid" ]; then
        # Try to find what port it's listening on
        if command -v lsof &>/dev/null; then
            port=$(lsof -Pan -p "$pid" -i TCP -sTCP:LISTEN 2>/dev/null | grep -oE ':\d+' | head -1 | tr -d ':') || true
        elif command -v ss &>/dev/null; then
            port=$(ss -tlnp 2>/dev/null | grep "pid=$pid" | grep -oE ':\d+' | head -1 | tr -d ':') || true
        fi

        DETECTED_METHOD="process"
        DETECTED_PORT="${port:-unknown}"
        DETECTED_INFO="PID: $pid"
        return 0
    fi

    return 1
}

# Layer 2: Docker container detection
detect_docker() {
    if ! command -v docker &>/dev/null; then
        return 1
    fi

    if ! docker info &>/dev/null 2>&1; then
        return 1
    fi

    local container_info=""
    local port=""

    # Check for container named onelist
    container_info=$(docker ps --filter "name=onelist" --format '{{.Names}}:{{.Ports}}' 2>/dev/null | head -1) || true

    if [ -z "$container_info" ]; then
        # Check for trinsiklabs/onelist image
        container_info=$(docker ps --filter "ancestor=trinsiklabs/onelist" --format '{{.Names}}:{{.Ports}}' 2>/dev/null | head -1) || true
    fi

    if [ -z "$container_info" ]; then
        # Check for any container with onelist in the image name
        container_info=$(docker ps --format '{{.Names}}:{{.Image}}:{{.Ports}}' 2>/dev/null | grep -i onelist | head -1) || true
    fi

    if [ -n "$container_info" ]; then
        # Extract port mapping (e.g., "0.0.0.0:4000->4000/tcp" -> "4000")
        port=$(echo "$container_info" | grep -oE '0\.0\.0\.0:[0-9]+' | head -1 | cut -d: -f2) || true
        if [ -z "$port" ]; then
            port=$(echo "$container_info" | grep -oE ':[0-9]+->' | head -1 | tr -d ':' | tr -d '->' ) || true
        fi

        DETECTED_METHOD="docker"
        DETECTED_PORT="${port:-unknown}"
        DETECTED_INFO="Container: $(echo "$container_info" | cut -d: -f1)"
        return 0
    fi

    return 1
}

# Layer 3: Config/installation file detection
detect_config() {
    local onelist_home="${ONELIST_HOME:-$HOME/.onelist}"

    # Check for onelist config file
    if [ -f "$onelist_home/config.json" ]; then
        DETECTED_METHOD="config"
        DETECTED_INFO="Found: $onelist_home/config.json"

        # Try to extract port from config
        if command -v jq &>/dev/null; then
            DETECTED_PORT=$(jq -r '.port // .server.port // "unknown"' "$onelist_home/config.json" 2>/dev/null) || true
        fi
        [ "$DETECTED_PORT" = "null" ] && DETECTED_PORT="unknown"

        return 0
    fi

    # Check for docker-compose.yml
    if [ -f "$onelist_home/docker-compose.yml" ]; then
        DETECTED_METHOD="config"
        DETECTED_INFO="Found: $onelist_home/docker-compose.yml"

        # Try to extract port from docker-compose
        DETECTED_PORT=$(grep -oE '\d+:4000' "$onelist_home/docker-compose.yml" 2>/dev/null | head -1 | cut -d: -f1) || true
        [ -z "$DETECTED_PORT" ] && DETECTED_PORT="unknown"

        return 0
    fi

    # Check /opt/onelist
    if [ -d "/opt/onelist" ]; then
        DETECTED_METHOD="config"
        DETECTED_INFO="Found: /opt/onelist/"
        DETECTED_PORT="unknown"
        return 0
    fi

    return 1
}

# Layer 4: Systemd service check
detect_systemd() {
    if ! command -v systemctl &>/dev/null; then
        return 1
    fi

    local status=""

    # Check for onelist service
    status=$(systemctl is-active onelist 2>/dev/null) || true

    if [ "$status" = "active" ]; then
        DETECTED_METHOD="systemd"
        DETECTED_INFO="Service: onelist.service (active)"

        # Try to get port from service file or environment
        local service_file="/etc/systemd/system/onelist.service"
        if [ -f "$service_file" ]; then
            DETECTED_PORT=$(grep -oE 'PORT=[0-9]+' "$service_file" 2>/dev/null | cut -d= -f2) || true
        fi
        [ -z "$DETECTED_PORT" ] && DETECTED_PORT="unknown"

        return 0
    fi

    # Check if service exists but is inactive
    if systemctl list-unit-files onelist.service &>/dev/null 2>&1; then
        status=$(systemctl is-enabled onelist 2>/dev/null) || true
        if [ "$status" = "enabled" ] || [ "$status" = "disabled" ]; then
            DETECTED_METHOD="systemd"
            DETECTED_INFO="Service: onelist.service (installed but not active)"
            DETECTED_PORT="unknown"
            return 0
        fi
    fi

    return 1
}

# Run all detection layers
run_detection() {
    DETECTED_METHOD=""
    DETECTED_PORT=""
    DETECTED_INFO=""

    # Layer 1: Process
    if detect_process; then
        return 0
    fi

    # Layer 2: Docker
    if detect_docker; then
        return 0
    fi

    # Layer 3: Config files
    if detect_config; then
        return 0
    fi

    # Layer 4: Systemd
    if detect_systemd; then
        return 0
    fi

    return 1
}

# Show detection results
show_detection() {
    echo ""
    echo -e "${BOLD}Onelist Detection Results${NC}"
    echo "────────────────────────────────────────────────────────────────────"

    echo ""
    echo "Running detection layers..."
    echo ""

    # Layer 1
    echo -n "  [1] Process detection:    "
    if detect_process; then
        echo -e "${GREEN}FOUND${NC} ($DETECTED_INFO, port: $DETECTED_PORT)"
    else
        echo -e "${DIM}not found${NC}"
    fi

    # Layer 2
    DETECTED_METHOD=""
    echo -n "  [2] Docker container:     "
    if detect_docker; then
        echo -e "${GREEN}FOUND${NC} ($DETECTED_INFO, port: $DETECTED_PORT)"
    else
        echo -e "${DIM}not found${NC}"
    fi

    # Layer 3
    DETECTED_METHOD=""
    echo -n "  [3] Config files:         "
    if detect_config; then
        echo -e "${GREEN}FOUND${NC} ($DETECTED_INFO)"
    else
        echo -e "${DIM}not found${NC}"
    fi

    # Layer 4
    DETECTED_METHOD=""
    echo -n "  [4] Systemd service:      "
    if detect_systemd; then
        echo -e "${GREEN}FOUND${NC} ($DETECTED_INFO)"
    else
        echo -e "${DIM}not found${NC}"
    fi

    echo ""
}

# Configure OCTO to connect to Onelist
configure_connection() {
    local url="$1"

    if [ -f "$OCTO_HOME/config.json" ] && command -v jq &>/dev/null; then
        local tmp=$(mktemp)
        jq --arg url "$url" '.onelist.url = $url | .onelist.connected = true' "$OCTO_HOME/config.json" > "$tmp"
        mv "$tmp" "$OCTO_HOME/config.json"
        log_ok "Configured OCTO to connect to $url"
    else
        log_warn "Could not update OCTO config (jq not available or config missing)"
    fi
}

# Remove Onelist connection from config
disconnect_onelist() {
    if [ -f "$OCTO_HOME/config.json" ] && command -v jq &>/dev/null; then
        local tmp=$(mktemp)
        jq '.onelist.url = null | .onelist.connected = false' "$OCTO_HOME/config.json" > "$tmp"
        mv "$tmp" "$OCTO_HOME/config.json"
        log_ok "Disconnected from Onelist"
    else
        log_warn "Could not update OCTO config"
    fi
}

# Show current status
show_status() {
    echo ""
    echo -e "${BOLD}Onelist Connection Status${NC}"
    echo "────────────────────────────────────────────────────────────────────"

    # Check config
    if [ -f "$OCTO_HOME/config.json" ] && command -v jq &>/dev/null; then
        local url=$(jq -r '.onelist.url // "not configured"' "$OCTO_HOME/config.json")
        local connected=$(jq -r '.onelist.connected // false' "$OCTO_HOME/config.json")

        echo -e "  Configured URL:         ${url}"
        echo -e "  Connected:              ${connected}"

        if [ "$connected" = "true" ] && [ "$url" != "null" ] && [ "$url" != "not configured" ]; then
            echo ""
            echo "  Checking connection..."
            if check_onelist_health "$url"; then
                echo -e "  Onelist Status:         ${GREEN}responding${NC}"
            else
                echo -e "  Onelist Status:         ${RED}not responding${NC}"
            fi
        fi
    else
        echo -e "  ${DIM}OCTO not configured or jq not available${NC}"
    fi

    echo ""

    # Also show detection
    show_detection
}

# Check system resources for Onelist requirements
check_resources() {
    local meets_requirements=true

    # RAM check (4GB required)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        RAM_GB=$(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 ))
    else
        RAM_GB=$(( $(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}') / 1024 / 1024 ))
    fi
    [ "$RAM_GB" -lt 4 ] && meets_requirements=false

    # CPU check (2 cores required)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        CPU_CORES=$(sysctl -n hw.ncpu)
    else
        CPU_CORES=$(nproc 2>/dev/null || echo "2")
    fi
    [ "$CPU_CORES" -lt 2 ] && meets_requirements=false

    # Disk check (10GB required)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        DISK_GB=$(df -g / 2>/dev/null | tail -1 | awk '{print $4}')
    else
        DISK_GB=$(df -BG / 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G')
    fi
    [ "${DISK_GB:-0}" -lt 10 ] && meets_requirements=false

    if [ "$meets_requirements" = true ]; then
        return 0
    fi
    return 1
}

# Offer to install onelist-local
offer_install() {
    echo ""
    echo -e "${YELLOW}Onelist is not installed.${NC}"
    echo ""
    echo "Would you like to install onelist-local?"
    echo "This will download and run the installer from:"
    echo -e "  ${DIM}$ONELIST_LOCAL_INSTALLER${NC}"
    echo ""

    # Check resources first
    echo "Checking system requirements..."
    if check_resources; then
        log_ok "RAM: ${RAM_GB}GB (4GB required)"
        log_ok "CPU: ${CPU_CORES} cores (2 required)"
        log_ok "Disk: ${DISK_GB:-?}GB available (10GB required)"
    else
        log_warn "RAM: ${RAM_GB}GB (4GB required)"
        log_warn "CPU: ${CPU_CORES} cores (2 required)"
        log_warn "Disk: ${DISK_GB:-?}GB available (10GB required)"
        echo ""
        log_warn "System may not meet Onelist requirements"
    fi

    echo ""
    read -p "Install onelist-local? [y/N] " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        echo "Downloading and running onelist-local installer..."
        echo ""

        # Download and run installer
        curl -fsSL "$ONELIST_LOCAL_INSTALLER" | bash

        echo ""
        echo "After installation completes, run 'octo onelist' again to connect."
    else
        echo ""
        echo "You can install onelist-local manually:"
        echo "  curl -fsSL $ONELIST_LOCAL_INSTALLER | bash"
        echo ""
        echo "Or connect to an existing Onelist instance:"
        echo "  octo onelist --url=http://your-onelist-host:4000"
    fi
}

# Handle detected but not responding scenario
handle_detected_not_responding() {
    echo ""
    echo -e "${YELLOW}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  Onelist Detected But Not Responding${NC}"
    echo -e "${YELLOW}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "  Detection method:       $DETECTED_METHOD"
    echo "  Details:                $DETECTED_INFO"
    echo "  Detected port:          $DETECTED_PORT"
    echo "  Checked URL:            $ONELIST_URL"
    echo ""
    echo -e "${BOLD}This could mean:${NC}"
    echo "  1. Onelist is installed but not currently running"
    echo "  2. Onelist is running on a different port"
    echo "  3. Onelist is starting up and not ready yet"
    echo ""

    if [ ! -t 0 ]; then
        # Non-interactive mode
        echo -e "${RED}Error:${NC} Onelist detected but not responding on standard port."
        echo ""
        echo "Options:"
        echo "  - Start Onelist and try again"
        echo "  - Specify the correct port: octo onelist --port=PORT"
        echo "  - Skip Onelist: octo onelist --disconnect"
        exit 1
    fi

    # Interactive mode - give options
    echo -e "${BOLD}What would you like to do?${NC}"
    echo ""
    echo "  1) Enter the correct port"
    echo "  2) Continue without Onelist support"
    echo "  3) Try to start Onelist (if you know how)"
    echo "  4) Cancel"
    echo ""

    while true; do
        read -p "  Enter choice [1-4]: " -r choice
        case $choice in
            1)
                echo ""
                read -p "  Enter Onelist port: " -r custom_port
                if [ -n "$custom_port" ]; then
                    ONELIST_PORT="$custom_port"
                    ONELIST_URL="http://localhost:$custom_port"
                    echo ""
                    echo "  Checking http://localhost:$custom_port..."
                    if check_onelist_health "$ONELIST_URL"; then
                        log_ok "Onelist responding at $ONELIST_URL"
                        configure_connection "$ONELIST_URL"
                        echo ""
                        echo -e "${GREEN}Connected to Onelist!${NC}"
                        exit 0
                    else
                        log_error "Onelist not responding at port $custom_port"
                        echo ""
                    fi
                fi
                ;;
            2)
                echo ""
                echo "Continuing without Onelist support."
                echo "OCTO standalone optimizations will still work."
                echo ""
                echo "Run 'octo onelist' anytime to connect to Onelist."
                exit 0
                ;;
            3)
                echo ""
                echo "Please start Onelist manually, then run 'octo onelist' again."
                echo ""
                echo "Common start commands:"
                echo "  Docker:  cd ~/.onelist && docker-compose up -d"
                echo "  Systemd: sudo systemctl start onelist"
                echo "  Native:  cd /opt/onelist && ./bin/onelist start"
                exit 0
                ;;
            4)
                echo ""
                echo "Cancelled."
                exit 0
                ;;
            *)
                echo "  Please enter 1, 2, 3, or 4"
                ;;
        esac
    done
}

# Parse arguments
ACTION=""
EXPLICIT_URL=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --url=*)
            ONELIST_URL="${1#*=}"
            EXPLICIT_URL=true
            shift
            ;;
        --url)
            ONELIST_URL="$2"
            EXPLICIT_URL=true
            shift 2
            ;;
        --port=*)
            ONELIST_PORT="${1#*=}"
            ONELIST_URL="http://localhost:$ONELIST_PORT"
            EXPLICIT_URL=true
            shift
            ;;
        --port)
            ONELIST_PORT="$2"
            ONELIST_URL="http://localhost:$ONELIST_PORT"
            EXPLICIT_URL=true
            shift 2
            ;;
        --status)
            ACTION="status"
            shift
            ;;
        --disconnect)
            ACTION="disconnect"
            shift
            ;;
        --detect)
            ACTION="detect"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Handle specific actions
case "$ACTION" in
    status)
        show_status
        exit 0
        ;;
    disconnect)
        disconnect_onelist
        exit 0
        ;;
    detect)
        show_detection
        exit 0
        ;;
esac

# Main flow
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}                ${BOLD}Onelist Integration${NC}                              ${CYAN}║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# If explicit URL provided, just check that
if [ "$EXPLICIT_URL" = true ]; then
    echo "Checking specified URL: $ONELIST_URL..."
    echo ""
    if check_onelist_health "$ONELIST_URL"; then
        log_ok "Onelist responding at $ONELIST_URL"
        configure_connection "$ONELIST_URL"
        echo ""
        echo -e "${GREEN}Connected to Onelist!${NC}"
        echo ""
        echo -e "  ${BOLD}Additional savings:${NC} ${GREEN}50-70%${NC} on top of OCTO optimizations"
        exit 0
    else
        log_error "Onelist not responding at $ONELIST_URL"
        exit 1
    fi
fi

# Run multi-layer detection
echo "Running Onelist detection..."
echo ""

if run_detection; then
    # Something was detected
    log_ok "Onelist detected via $DETECTED_METHOD"
    log_info "$DETECTED_INFO"

    # Determine URL to check
    if [ "$DETECTED_PORT" != "unknown" ] && [ -n "$DETECTED_PORT" ]; then
        ONELIST_URL="http://localhost:$DETECTED_PORT"
    fi

    echo ""
    echo "  Checking $ONELIST_URL..."

    if check_onelist_health "$ONELIST_URL"; then
        log_ok "Onelist responding"
        echo ""
        configure_connection "$ONELIST_URL"

        echo ""
        echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}  Connected to Onelist!${NC}"
        echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
        echo ""
        echo "  Onelist URL:            $ONELIST_URL"
        echo ""
        echo -e "  ${BOLD}Additional savings:${NC} ${GREEN}50-70%${NC} on top of OCTO optimizations"
        echo ""
        echo "  Commands:"
        echo "    octo onelist --status     Check connection status"
        echo "    octo onelist --disconnect Remove connection"
        echo ""
    else
        # Detected but not responding
        handle_detected_not_responding
    fi
else
    # Nothing detected
    log_warn "Onelist not detected"

    # Interactive mode - offer to install
    if [ -t 0 ]; then
        offer_install
    else
        # Non-interactive mode
        echo ""
        echo "Install onelist-local:"
        echo "  curl -fsSL $ONELIST_LOCAL_INSTALLER | bash"
        echo ""
        echo "Or specify a URL:"
        echo "  octo onelist --url=http://your-onelist-host:4000"
        exit 1
    fi
fi
