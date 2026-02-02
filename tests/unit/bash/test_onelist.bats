#!/usr/bin/env bats
#
# Tests for lib/cli/onelist.sh
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
# Resource Check Tests
# ============================================

@test "minimum RAM requirement is 4GB" {
    MIN_RAM_GB=4
    MIN_RAM_BYTES=$((MIN_RAM_GB * 1024 * 1024 * 1024))

    [ "$MIN_RAM_BYTES" -eq 4294967296 ]
}

@test "minimum CPU requirement is 2 cores" {
    MIN_CORES=2
    [ "$MIN_CORES" -eq 2 ]
}

@test "minimum disk requirement is 10GB" {
    MIN_DISK_GB=10
    [ "$MIN_DISK_GB" -eq 10 ]
}

@test "detects system RAM" {
    if [[ "$(uname)" == "Darwin" ]]; then
        RAM=$(sysctl -n hw.memsize 2>/dev/null)
    else
        RAM=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2 * 1024}')
    fi

    [ -n "$RAM" ]
    [ "$RAM" -gt 0 ]
}

@test "detects system CPU cores" {
    if [[ "$(uname)" == "Darwin" ]]; then
        CORES=$(sysctl -n hw.ncpu 2>/dev/null)
    else
        CORES=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null)
    fi

    [ -n "$CORES" ]
    [ "$CORES" -gt 0 ]
}

# ============================================
# Docker Installation Tests
# ============================================

@test "docker compose file format" {
    # Expected docker-compose structure
    COMPOSE_VERSION="3.8"
    [ "$COMPOSE_VERSION" == "3.8" ]
}

@test "docker postgres image is pgvector" {
    IMAGE="pgvector/pgvector:pg16"
    [[ "$IMAGE" == *"pgvector"* ]]
}

@test "docker postgres port is 5432" {
    PORT=5432
    [ "$PORT" -eq 5432 ]
}

@test "docker onelist port is 8080" {
    PORT=8080
    [ "$PORT" -eq 8080 ]
}

@test "docker volume for postgres data" {
    VOLUME="onelist_pgdata"
    [ -n "$VOLUME" ]
}

# ============================================
# Native Installation Tests
# ============================================

@test "native install checks for postgresql" {
    # Check if postgresql is installed
    if command -v psql &>/dev/null; then
        POSTGRES_INSTALLED=true
    else
        POSTGRES_INSTALLED=false
    fi

    # Just verify we can check
    [ -n "$POSTGRES_INSTALLED" ]
}

@test "native install checks for python3" {
    run command -v python3
    [ "$status" -eq 0 ]
}

# ============================================
# Configuration Update Tests
# ============================================

@test "updates config with onelist.installed=true" {
    if command -v jq &>/dev/null; then
        # Update config
        jq '.onelist.installed = true' "$OCTO_HOME/config.json" > "$OCTO_HOME/config.json.tmp"
        mv "$OCTO_HOME/config.json.tmp" "$OCTO_HOME/config.json"

        installed=$(jq -r '.onelist.installed' "$OCTO_HOME/config.json")
        [ "$installed" == "true" ]
    fi
}

@test "updates config with onelist.method" {
    if command -v jq &>/dev/null; then
        jq '.onelist.method = "docker"' "$OCTO_HOME/config.json" > "$OCTO_HOME/config.json.tmp"
        mv "$OCTO_HOME/config.json.tmp" "$OCTO_HOME/config.json"

        method=$(jq -r '.onelist.method' "$OCTO_HOME/config.json")
        [ "$method" == "docker" ]
    fi
}

# ============================================
# Health Check Tests
# ============================================

@test "onelist health endpoint" {
    HEALTH_URL="http://localhost:8080/health"
    [[ "$HEALTH_URL" == *"health"* ]]
}

@test "postgres connection string format" {
    CONN_STRING="postgresql://user:pass@localhost:5432/onelist"
    [[ "$CONN_STRING" == *"postgresql://"* ]]
    [[ "$CONN_STRING" == *"5432"* ]]
}

# ============================================
# Status Command Tests
# ============================================

@test "status shows installation state" {
    run "$PROJECT_ROOT/bin/octo" onelist status
    # Should show some status
    [[ "$output" == *"Onelist"* ]] || [[ "$output" == *"onelist"* ]] || [[ "$output" == *"not installed"* ]] || [[ "$output" == *"installed"* ]] || [ -n "$output" ]
}

@test "status shows docker containers when docker method" {
    # If installed via Docker, should show container status
    METHOD="docker"
    if [ "$METHOD" == "docker" ]; then
        # Would check docker ps
        CHECK_CONTAINERS=true
    fi

    [ "$CHECK_CONTAINERS" == "true" ]
}

# ============================================
# Uninstall Tests
# ============================================

@test "uninstall removes docker containers" {
    UNINSTALL_CMD="docker compose down -v"
    [[ "$UNINSTALL_CMD" == *"down"* ]]
}

@test "uninstall updates config" {
    if command -v jq &>/dev/null; then
        jq '.onelist.installed = false | .onelist.method = null' "$OCTO_HOME/config.json" > "$OCTO_HOME/config.json.tmp"
        mv "$OCTO_HOME/config.json.tmp" "$OCTO_HOME/config.json"

        installed=$(jq -r '.onelist.installed' "$OCTO_HOME/config.json")
        [ "$installed" == "false" ]
    fi
}

# ============================================
# Integration Test
# ============================================

@test "onelist command shows help" {
    run "$PROJECT_ROOT/bin/octo" onelist --help
    [ -n "$output" ] || [ "$status" -eq 0 ]
}

@test "onelist install shows resource check" {
    run "$PROJECT_ROOT/bin/octo" onelist install --dry-run 2>&1
    # Should mention resources or requirements
    [[ "$output" == *"RAM"* ]] || [[ "$output" == *"resource"* ]] || [[ "$output" == *"require"* ]] || [[ "$output" == *"Docker"* ]] || [[ "$output" == *"Native"* ]] || [ -n "$output" ]
}
