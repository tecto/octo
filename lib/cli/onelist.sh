#!/usr/bin/env bash
#
# OCTO Onelist Integration
# Install and configure Onelist local inference
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")"
OCTO_HOME="${OCTO_HOME:-$HOME/.octo}"
OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Default configuration
INSTALL_METHOD=""
ONELIST_PORT=4000
PG_PORT=5432
ONELIST_DB="onelist_dev"

show_help() {
    echo "Usage: octo onelist [options]"
    echo ""
    echo "Install and configure Onelist local inference for maximum savings."
    echo ""
    echo "Options:"
    echo "  --method=METHOD    Installation method: docker or native"
    echo "  --port=PORT        Onelist port (default: 4000)"
    echo "  --db=NAME          Database name (default: onelist_dev)"
    echo "  --check            Check if system meets requirements"
    echo "  --status           Show Onelist status"
    echo "  -h, --help         Show this help"
    echo ""
    echo "Examples:"
    echo "  octo onelist                    # Interactive install"
    echo "  octo onelist --method=docker    # Docker installation"
    echo "  octo onelist --method=native    # Native installation"
    echo "  octo onelist --status           # Check status"
}

log_step() {
    echo -e "\n${CYAN}[•]${NC} ${BOLD}$1${NC}"
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

check_requirements() {
    log_step "Checking system requirements..."

    local meets_requirements=true

    # RAM check
    if [[ "$OSTYPE" == "darwin"* ]]; then
        RAM_GB=$(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 ))
    else
        RAM_GB=$(( $(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 / 1024 ))
    fi

    if [ "$RAM_GB" -ge 4 ]; then
        log_ok "RAM: ${RAM_GB}GB (4GB required)"
    else
        log_error "RAM: ${RAM_GB}GB (4GB required)"
        meets_requirements=false
    fi

    # CPU check
    if [[ "$OSTYPE" == "darwin"* ]]; then
        CPU_CORES=$(sysctl -n hw.ncpu)
    else
        CPU_CORES=$(nproc)
    fi

    if [ "$CPU_CORES" -ge 2 ]; then
        log_ok "CPU: ${CPU_CORES} cores (2 required)"
    else
        log_error "CPU: ${CPU_CORES} cores (2 required)"
        meets_requirements=false
    fi

    # Disk check
    DISK_GB=$(df -BG "$HOME" 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G' || echo "0")
    if [ "$DISK_GB" -ge 10 ]; then
        log_ok "Disk: ${DISK_GB}GB available (10GB required)"
    else
        log_error "Disk: ${DISK_GB}GB available (10GB required)"
        meets_requirements=false
    fi

    # Check for Docker (if docker method)
    if [ "$INSTALL_METHOD" = "docker" ] || [ -z "$INSTALL_METHOD" ]; then
        if command -v docker &>/dev/null; then
            DOCKER_VERSION=$(docker --version | cut -d' ' -f3 | tr -d ',')
            log_ok "Docker: $DOCKER_VERSION"

            if docker info &>/dev/null; then
                log_ok "Docker daemon running"
            else
                log_warn "Docker daemon not running"
            fi
        else
            log_info "Docker: not installed"
        fi
    fi

    # Check for PostgreSQL (if native method)
    if [ "$INSTALL_METHOD" = "native" ] || [ -z "$INSTALL_METHOD" ]; then
        if command -v psql &>/dev/null; then
            PG_VERSION=$(psql --version | cut -d' ' -f3)
            log_ok "PostgreSQL: $PG_VERSION"

            if pg_isready -q 2>/dev/null; then
                log_ok "PostgreSQL running"
            else
                log_info "PostgreSQL not running"
            fi
        else
            log_info "PostgreSQL: not installed"
        fi
    fi

    if [ "$meets_requirements" = false ]; then
        echo ""
        log_error "System does not meet minimum requirements"
        return 1
    fi

    return 0
}

show_status() {
    echo ""
    echo -e "${BOLD}Onelist Status${NC}"
    echo "────────────────────────────────────────────────────────────────────"

    # Check config
    if [ -f "$OCTO_HOME/config.json" ]; then
        INSTALLED=$(jq -r '.onelist.installed // false' "$OCTO_HOME/config.json")
        METHOD=$(jq -r '.onelist.method // "unknown"' "$OCTO_HOME/config.json")

        if [ "$INSTALLED" = "true" ]; then
            echo -e "  Installation:           ${GREEN}installed${NC} ($METHOD)"
        else
            echo -e "  Installation:           ${DIM}not installed${NC}"
            return
        fi
    else
        echo -e "  ${DIM}OCTO not configured${NC}"
        return
    fi

    # Check PostgreSQL
    if pg_isready -q 2>/dev/null; then
        echo -e "  PostgreSQL:             ${GREEN}running${NC}"
    else
        echo -e "  PostgreSQL:             ${RED}not running${NC}"
    fi

    # Check Onelist service
    if pgrep -f "beam.smp" >/dev/null 2>&1; then
        echo -e "  Onelist Service:        ${GREEN}running${NC}"
    elif [ "$METHOD" = "docker" ] && docker ps --format '{{.Names}}' 2>/dev/null | grep -q onelist; then
        echo -e "  Onelist Container:      ${GREEN}running${NC}"
    else
        echo -e "  Onelist Service:        ${RED}not running${NC}"
    fi

    # Check memory plugin
    MEMORY_PLUGIN="$OPENCLAW_HOME/plugins/onelist-memory"
    if [ -d "$MEMORY_PLUGIN" ]; then
        echo -e "  Memory Plugin:          ${GREEN}installed${NC}"
    else
        echo -e "  Memory Plugin:          ${DIM}not installed${NC}"
    fi

    echo ""
}

install_docker() {
    log_step "Installing Onelist via Docker..."

    # Check Docker is available
    if ! command -v docker &>/dev/null; then
        log_error "Docker is required for this installation method"
        echo ""
        echo "Install Docker from: https://docs.docker.com/get-docker/"
        return 1
    fi

    if ! docker info &>/dev/null; then
        log_error "Docker daemon is not running"
        return 1
    fi

    # Check docker-compose
    if command -v docker-compose &>/dev/null; then
        COMPOSE_CMD="docker-compose"
    elif docker compose version &>/dev/null; then
        COMPOSE_CMD="docker compose"
    else
        log_error "docker-compose not found"
        return 1
    fi

    # Create directory
    ONELIST_DIR="$HOME/.onelist"
    mkdir -p "$ONELIST_DIR"

    # Generate docker-compose.yml
    log_info "Creating docker-compose configuration..."

    cat > "$ONELIST_DIR/docker-compose.yml" << EOF
version: '3.8'

services:
  postgres:
    image: pgvector/pgvector:pg16
    container_name: onelist-postgres
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: ${ONELIST_DB}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "${PG_PORT}:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5

  onelist:
    image: trinsiklabs/onelist:latest
    container_name: onelist
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      DATABASE_URL: postgres://postgres:postgres@postgres:5432/${ONELIST_DB}
      SECRET_KEY_BASE: $(openssl rand -hex 32)
      PHX_HOST: localhost
    ports:
      - "${ONELIST_PORT}:4000"
    restart: unless-stopped

volumes:
  postgres_data:
EOF

    log_ok "docker-compose.yml created"

    # Start containers
    log_info "Starting containers (this may take a few minutes)..."

    cd "$ONELIST_DIR"
    $COMPOSE_CMD pull
    $COMPOSE_CMD up -d

    # Wait for services
    log_info "Waiting for services to start..."
    sleep 10

    # Verify
    if curl -s "http://localhost:${ONELIST_PORT}/health" >/dev/null 2>&1; then
        log_ok "Onelist is running at http://localhost:${ONELIST_PORT}"
    else
        log_warn "Onelist may still be starting..."
        log_info "Check status with: octo onelist --status"
    fi

    return 0
}

install_native() {
    log_step "Installing Onelist natively..."

    # Check PostgreSQL
    if ! command -v psql &>/dev/null; then
        log_error "PostgreSQL is required for native installation"
        echo ""
        echo "Install PostgreSQL 14+ first, then run this command again."
        return 1
    fi

    if ! pg_isready -q 2>/dev/null; then
        log_error "PostgreSQL is not running"
        return 1
    fi

    # Check pgvector extension
    log_info "Checking pgvector extension..."

    HAS_PGVECTOR=$(sudo -u postgres psql -t -c "SELECT 1 FROM pg_available_extensions WHERE name = 'vector';" 2>/dev/null | tr -d ' ')

    if [ "$HAS_PGVECTOR" != "1" ]; then
        log_warn "pgvector extension not found"
        log_info "Attempting to install pgvector..."

        if [[ "$OSTYPE" == "darwin"* ]]; then
            if command -v brew &>/dev/null; then
                brew install pgvector
            else
                log_error "Please install pgvector: brew install pgvector"
                return 1
            fi
        else
            # Debian/Ubuntu
            if command -v apt-get &>/dev/null; then
                sudo apt-get update
                sudo apt-get install -y postgresql-16-pgvector || sudo apt-get install -y postgresql-15-pgvector || sudo apt-get install -y postgresql-14-pgvector
            else
                log_error "Please install pgvector for your system"
                return 1
            fi
        fi
    fi

    # Create database
    log_info "Creating database..."

    sudo -u postgres psql << EOF
CREATE DATABASE ${ONELIST_DB};
\c ${ONELIST_DB}
CREATE EXTENSION IF NOT EXISTS vector;
EOF

    log_ok "Database created with pgvector extension"

    # Download Onelist
    log_info "Downloading Onelist..."

    ONELIST_DIR="$HOME/.onelist"
    mkdir -p "$ONELIST_DIR"

    # TODO: Replace with actual Onelist download URL
    # curl -L "https://github.com/trinsiklabs/onelist/releases/latest/download/onelist-linux-amd64.tar.gz" | tar xz -C "$ONELIST_DIR"

    log_warn "Native installation requires manual Onelist binary download"
    log_info "Please download from: https://github.com/trinsiklabs/onelist/releases"

    return 0
}

configure_memory_plugin() {
    log_step "Configuring OpenClaw memory plugin..."

    # Create plugin directory
    MEMORY_PLUGIN="$OPENCLAW_HOME/plugins/onelist-memory"
    mkdir -p "$MEMORY_PLUGIN"

    # Create plugin configuration
    cat > "$MEMORY_PLUGIN/config.json" << EOF
{
  "name": "onelist-memory",
  "version": "1.0.0",
  "onelistUrl": "http://localhost:${ONELIST_PORT}",
  "enabled": true,
  "maxInjections": 3,
  "searchLimit": 10
}
EOF

    log_ok "Memory plugin configured"

    # Update OCTO config
    if [ -f "$OCTO_HOME/config.json" ]; then
        local tmp=$(mktemp)
        jq ".onelist.installed = true | .onelist.method = \"$INSTALL_METHOD\" | .onelist.port = $ONELIST_PORT" "$OCTO_HOME/config.json" > "$tmp"
        mv "$tmp" "$OCTO_HOME/config.json"
        log_ok "OCTO configuration updated"
    fi
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --method=*)
            INSTALL_METHOD="${1#*=}"
            shift
            ;;
        --method)
            INSTALL_METHOD="$2"
            shift 2
            ;;
        --port=*)
            ONELIST_PORT="${1#*=}"
            shift
            ;;
        --db=*)
            ONELIST_DB="${1#*=}"
            shift
            ;;
        --check)
            check_requirements
            exit $?
            ;;
        --status)
            show_status
            exit 0
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

# Check if already installed
check_already_installed() {
    if [ -f "$OCTO_HOME/config.json" ]; then
        local installed=$(jq -r '.onelist.installed // false' "$OCTO_HOME/config.json" 2>/dev/null)
        if [ "$installed" = "true" ]; then
            return 0
        fi
    fi
    return 1
}

# Main installation flow
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}                ${BOLD}Onelist Installation${NC}                             ${CYAN}║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"

# Check if already installed
if check_already_installed; then
    echo ""
    log_ok "Onelist is already installed"
    show_status

    # In interactive mode, ask if they want to reinstall
    if [ -t 0 ]; then
        echo ""
        echo -n "  Reinstall Onelist? [y/N] "
        read -r reply
        if [[ ! "$reply" =~ ^[Yy]$ ]]; then
            echo ""
            echo "  Run 'octo onelist --status' to check status"
            exit 0
        fi
        echo ""
        log_warn "Proceeding with reinstallation..."
    else
        # Non-interactive mode - just exit successfully
        exit 0
    fi
fi

# Check requirements
check_requirements || exit 1

# Method selection
if [ -z "$INSTALL_METHOD" ]; then
    echo ""
    echo -e "${BOLD}Select installation method:${NC}"
    echo ""
    echo "  1) Docker (recommended for most users)"
    echo "     - Single command, isolated environment"
    echo "     - Requires Docker Desktop or Docker Engine"
    echo ""
    echo "  2) Native (recommended if you have PostgreSQL)"
    echo "     - Better performance, less overhead"
    echo "     - Requires PostgreSQL 14+ with pgvector"
    echo ""

    while true; do
        echo -n "  Enter choice [1/2]: "
        read -r choice
        case $choice in
            1) INSTALL_METHOD="docker"; break ;;
            2) INSTALL_METHOD="native"; break ;;
            *) echo "  Please enter 1 or 2" ;;
        esac
    done
fi

# Run installation
case "$INSTALL_METHOD" in
    docker)
        install_docker
        ;;
    native)
        install_native
        ;;
    *)
        log_error "Unknown installation method: $INSTALL_METHOD"
        exit 1
        ;;
esac

# Configure plugin
configure_memory_plugin

# Summary
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Onelist Installation Complete!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo "  Onelist URL:            http://localhost:${ONELIST_PORT}"
echo "  Memory Plugin:          $OPENCLAW_HOME/plugins/onelist-memory"
echo ""
echo -e "  ${BOLD}Additional savings:${NC} ${GREEN}50-70%${NC} on top of OCTO optimizations"
echo ""
echo "  Commands:"
echo "    octo onelist --status     Check Onelist status"
echo "    octo pg-health            PostgreSQL maintenance"
echo ""
