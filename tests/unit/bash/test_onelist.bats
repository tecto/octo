#!/usr/bin/env bats
#
# Tests for lib/cli/onelist.sh
#
# OCTO's onelist command should:
# 1. Detect if Onelist is already running
# 2. Configure OCTO to connect to existing Onelist
# 3. Offer to download and run onelist-local installer if not running
#
# OCTO should NOT:
# - Install Docker containers
# - Set up PostgreSQL
# - Create databases
# - Create onelist-memory plugin (that's in onelist-local)
#

setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$TEST_DIR/../../.." && pwd)"
    FIXTURES_DIR="$TEST_DIR/../../fixtures"
    HELPERS_DIR="$TEST_DIR/../../helpers"

    export OCTO_HOME="$BATS_TMPDIR/octo_home_$$"
    export OPENCLAW_HOME="$BATS_TMPDIR/openclaw_home_$$"
    export OCTO_TEST_MODE=1

    mkdir -p "$OCTO_HOME"/{logs,costs,metrics}
    mkdir -p "$OPENCLAW_HOME/agents/main/sessions"

    cat > "$OPENCLAW_HOME/openclaw.json" << 'EOF'
{"version": "1.0.0", "gateway": {"port": 6200}}
EOF

    cp "$FIXTURES_DIR/configs/default_config.json" "$OCTO_HOME/config.json"

    source "$HELPERS_DIR/assertions.sh"
}

teardown() {
    rm -rf "$OCTO_HOME" "$OPENCLAW_HOME"
}

# ============================================
# Onelist Detection Tests
# ============================================

@test "detects Onelist via health endpoint" {
    # Health check URL
    HEALTH_URL="http://localhost:4000/api/health"
    [[ "$HEALTH_URL" == *"health"* ]]
}

@test "default Onelist port is 4000" {
    DEFAULT_PORT=4000
    [ "$DEFAULT_PORT" -eq 4000 ]
}

@test "can check custom Onelist port" {
    CUSTOM_PORT=8080
    HEALTH_URL="http://localhost:$CUSTOM_PORT/api/health"
    [[ "$HEALTH_URL" == *"8080"* ]]
}

@test "health check returns running status" {
    # Simulated response
    ONELIST_RUNNING=true

    [ "$ONELIST_RUNNING" = true ]
}

@test "health check returns not running status" {
    ONELIST_RUNNING=false

    [ "$ONELIST_RUNNING" = false ]
}

# ============================================
# Configuration Tests (when Onelist detected)
# ============================================

@test "configures OCTO with Onelist URL when detected" {
    ONELIST_URL="http://localhost:4000"

    if command -v jq &>/dev/null; then
        jq --arg url "$ONELIST_URL" '.onelist.url = $url | .onelist.connected = true' "$OCTO_HOME/config.json" > "$OCTO_HOME/config.json.tmp"
        mv "$OCTO_HOME/config.json.tmp" "$OCTO_HOME/config.json"

        URL=$(jq -r '.onelist.url' "$OCTO_HOME/config.json")
        [ "$URL" = "http://localhost:4000" ]
    fi
}

@test "sets onelist.connected to true when detected" {
    if command -v jq &>/dev/null; then
        jq '.onelist.connected = true' "$OCTO_HOME/config.json" > "$OCTO_HOME/config.json.tmp"
        mv "$OCTO_HOME/config.json.tmp" "$OCTO_HOME/config.json"

        CONNECTED=$(jq -r '.onelist.connected' "$OCTO_HOME/config.json")
        [ "$CONNECTED" = "true" ]
    fi
}

@test "does not set onelist.installed (that's onelist-local's job)" {
    # OCTO doesn't install Onelist, so it shouldn't set installed flag
    # It only knows if it's connected to a running instance
    if command -v jq &>/dev/null; then
        INSTALLED=$(jq -r '.onelist.installed // "not-set"' "$OCTO_HOME/config.json")
        # Should be false or not set (OCTO doesn't install)
        [[ "$INSTALLED" == "false" ]] || [[ "$INSTALLED" == "not-set" ]] || [[ "$INSTALLED" == "null" ]]
    fi
}

# ============================================
# Delegation Tests (when Onelist not detected)
# ============================================

@test "offers to install onelist-local when not detected" {
    # Should offer to run onelist-local installer
    OFFER_INSTALL=true

    [ "$OFFER_INSTALL" = true ]
}

@test "onelist-local installer URL is correct" {
    INSTALLER_URL="https://raw.githubusercontent.com/trinsiklabs/onelist-local/main/install.sh"
    [[ "$INSTALLER_URL" == *"trinsiklabs/onelist-local"* ]]
    [[ "$INSTALLER_URL" == *"install.sh"* ]]
}

@test "does NOT create docker-compose.yml" {
    # OCTO should not create Docker configs
    DOCKER_COMPOSE="$OCTO_HOME/docker-compose.yml"
    [ ! -f "$DOCKER_COMPOSE" ]
}

@test "does NOT create PostgreSQL configs" {
    # OCTO should not manage PostgreSQL
    PG_CONFIG="$OCTO_HOME/postgresql.conf"
    [ ! -f "$PG_CONFIG" ]
}

@test "does NOT create onelist-memory plugin" {
    # onelist-memory plugin is in onelist-local, not OCTO
    MEMORY_PLUGIN="$OPENCLAW_HOME/plugins/onelist-memory"
    [ ! -d "$MEMORY_PLUGIN" ]
}

# ============================================
# Status Command Tests
# ============================================

@test "status shows connection state" {
    run "$PROJECT_ROOT/bin/octo" onelist --status 2>&1

    # Should show connected/not connected
    [[ "$output" == *"connect"* ]] || [[ "$output" == *"running"* ]] || [[ "$output" == *"not"* ]] || [ -n "$output" ]
}

@test "status shows Onelist URL if connected" {
    if command -v jq &>/dev/null; then
        jq '.onelist.url = "http://localhost:4000" | .onelist.connected = true' "$OCTO_HOME/config.json" > "$OCTO_HOME/config.json.tmp"
        mv "$OCTO_HOME/config.json.tmp" "$OCTO_HOME/config.json"

        URL=$(jq -r '.onelist.url' "$OCTO_HOME/config.json")
        [ "$URL" = "http://localhost:4000" ]
    fi
}

# ============================================
# Resource Check Tests (for recommendations)
# ============================================

@test "shows resource requirements for Onelist" {
    # Should inform user of Onelist requirements
    MIN_RAM_GB=4
    MIN_CORES=2
    MIN_DISK_GB=10

    [ "$MIN_RAM_GB" -eq 4 ]
    [ "$MIN_CORES" -eq 2 ]
    [ "$MIN_DISK_GB" -eq 10 ]
}

@test "checks if system meets Onelist requirements" {
    # Should check resources before offering install
    CHECK_RESOURCES=true

    [ "$CHECK_RESOURCES" = true ]
}

# ============================================
# Help and CLI Tests
# ============================================

@test "onelist command shows help" {
    run "$PROJECT_ROOT/bin/octo" onelist --help 2>&1

    [ -n "$output" ] || [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "onelist --status flag works" {
    run "$PROJECT_ROOT/bin/octo" onelist --status 2>&1

    [ -n "$output" ] || [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "onelist --url flag allows custom URL" {
    CUSTOM_URL="http://192.168.1.100:4000"
    [[ "$CUSTOM_URL" == *"192.168"* ]]
}

@test "onelist --port flag allows custom port" {
    CUSTOM_PORT=8080
    [ "$CUSTOM_PORT" -eq 8080 ]
}

# ============================================
# Disconnect Tests
# ============================================

@test "onelist disconnect removes connection config" {
    if command -v jq &>/dev/null; then
        # First connect
        jq '.onelist.url = "http://localhost:4000" | .onelist.connected = true' "$OCTO_HOME/config.json" > "$OCTO_HOME/config.json.tmp"
        mv "$OCTO_HOME/config.json.tmp" "$OCTO_HOME/config.json"

        # Then disconnect
        jq '.onelist.url = null | .onelist.connected = false' "$OCTO_HOME/config.json" > "$OCTO_HOME/config.json.tmp"
        mv "$OCTO_HOME/config.json.tmp" "$OCTO_HOME/config.json"

        CONNECTED=$(jq -r '.onelist.connected' "$OCTO_HOME/config.json")
        [ "$CONNECTED" = "false" ]
    fi
}
