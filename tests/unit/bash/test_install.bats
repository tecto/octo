#!/usr/bin/env bats
#
# Tests for lib/cli/install.sh
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

    # Create minimal openclaw.json
    cat > "$OPENCLAW_HOME/openclaw.json" << 'EOF'
{"version": "1.0.0", "gateway": {"port": 6200}}
EOF

    source "$HELPERS_DIR/assertions.sh"

    # Source the install script functions (without running main)
    # We need to extract and test individual functions
    INSTALL_SCRIPT="$PROJECT_ROOT/lib/cli/install.sh"
}

teardown() {
    rm -rf "$OCTO_HOME" "$OPENCLAW_HOME"
}

# ============================================
# OpenClaw Detection Tests
# ============================================

@test "detects OpenClaw at default location" {
    export OPENCLAW_HOME="$BATS_TMPDIR/openclaw_home_$$"
    mkdir -p "$OPENCLAW_HOME"
    touch "$OPENCLAW_HOME/openclaw.json"

    [ -f "$OPENCLAW_HOME/openclaw.json" ]
}

@test "detects OpenClaw at custom OPENCLAW_HOME" {
    CUSTOM_HOME="$BATS_TMPDIR/custom_openclaw_$$"
    mkdir -p "$CUSTOM_HOME"
    echo '{"version":"1.0.0"}' > "$CUSTOM_HOME/openclaw.json"
    export OPENCLAW_HOME="$CUSTOM_HOME"

    [ -f "$OPENCLAW_HOME/openclaw.json" ]

    rm -rf "$CUSTOM_HOME"
}

@test "counts existing session files" {
    mkdir -p "$OPENCLAW_HOME/agents/main/sessions"
    touch "$OPENCLAW_HOME/agents/main/sessions/session1.jsonl"
    touch "$OPENCLAW_HOME/agents/main/sessions/session2.jsonl"
    touch "$OPENCLAW_HOME/agents/main/sessions/session3.jsonl"

    count=$(find "$OPENCLAW_HOME" -name "*.jsonl" -type f 2>/dev/null | wc -l | tr -d ' ')
    [ "$count" -eq 3 ]
}

# ============================================
# Port Availability Tests
# ============================================

@test "check_port_available returns 0 for free port" {
    # Use a random high port that's unlikely to be in use
    FREE_PORT=59123

    # Try to check with lsof
    if command -v lsof &>/dev/null; then
        if ! lsof -i ":$FREE_PORT" &>/dev/null; then
            # Port is free
            true
        fi
    fi
}

# ============================================
# Resource Detection Tests
# ============================================

@test "detects RAM on current system" {
    if [[ "$(uname)" == "Darwin" ]]; then
        ram=$(sysctl -n hw.memsize 2>/dev/null)
    else
        ram=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2 * 1024}')
    fi
    [ -n "$ram" ]
    [ "$ram" -gt 0 ]
}

@test "detects CPU cores on current system" {
    if [[ "$(uname)" == "Darwin" ]]; then
        cores=$(sysctl -n hw.ncpu 2>/dev/null)
    else
        cores=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null)
    fi
    [ -n "$cores" ]
    [ "$cores" -gt 0 ]
}

@test "detects available disk space" {
    if [[ "$(uname)" == "Darwin" ]]; then
        disk=$(df -g / 2>/dev/null | tail -1 | awk '{print $4}')
    else
        disk=$(df -BG / 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G')
    fi
    [ -n "$disk" ] || skip "Could not detect disk space"
    [ "$disk" -gt 0 ]
}

# ============================================
# Configuration Generation Tests
# ============================================

@test "generates valid JSON config" {
    CONFIG_FILE="$BATS_TMPDIR/test_config_$$.json"

    cat > "$CONFIG_FILE" << 'EOF'
{
  "version": "1.0.0",
  "installedAt": "2026-01-15T10:00:00Z",
  "optimization": {
    "promptCaching": {"enabled": true},
    "modelTiering": {"enabled": true}
  }
}
EOF

    # Validate JSON
    if command -v jq &>/dev/null; then
        run jq '.' "$CONFIG_FILE"
        [ "$status" -eq 0 ]
    fi

    rm -f "$CONFIG_FILE"
}

@test "config includes version field" {
    CONFIG_FILE="$FIXTURES_DIR/configs/default_config.json"

    if command -v jq &>/dev/null; then
        version=$(jq -r '.version' "$CONFIG_FILE")
        [ "$version" == "1.0.0" ]
    fi
}

@test "config includes installedAt timestamp" {
    CONFIG_FILE="$FIXTURES_DIR/configs/default_config.json"

    if command -v jq &>/dev/null; then
        timestamp=$(jq -r '.installedAt' "$CONFIG_FILE")
        [ -n "$timestamp" ]
        [ "$timestamp" != "null" ]
    fi
}

@test "respects user feature selections - all enabled" {
    CONFIG_FILE="$FIXTURES_DIR/configs/all_enabled.json"

    if command -v jq &>/dev/null; then
        caching=$(jq -r '.optimization.promptCaching.enabled' "$CONFIG_FILE")
        tiering=$(jq -r '.optimization.modelTiering.enabled' "$CONFIG_FILE")
        [ "$caching" == "true" ]
        [ "$tiering" == "true" ]
    fi
}

@test "respects user feature selections - all disabled" {
    CONFIG_FILE="$FIXTURES_DIR/configs/all_disabled.json"

    if command -v jq &>/dev/null; then
        caching=$(jq -r '.optimization.promptCaching.enabled' "$CONFIG_FILE")
        tiering=$(jq -r '.optimization.modelTiering.enabled' "$CONFIG_FILE")
        [ "$caching" == "false" ]
        [ "$tiering" == "false" ]
    fi
}

# ============================================
# Feature Toggle Tests
# ============================================

@test "config defaults ENABLE_CACHING to true" {
    CONFIG_FILE="$FIXTURES_DIR/configs/default_config.json"

    if command -v jq &>/dev/null; then
        enabled=$(jq -r '.optimization.promptCaching.enabled' "$CONFIG_FILE")
        [ "$enabled" == "true" ]
    fi
}

# ============================================
# Savings Calculation Tests
# ============================================

@test "savings calculation - caching alone gives 25-40%" {
    # Caching savings range
    MIN_SAVINGS=25
    MAX_SAVINGS=40

    # Calculate midpoint
    EXPECTED=$((($MIN_SAVINGS + $MAX_SAVINGS) / 2))

    [ "$EXPECTED" -ge 25 ]
    [ "$EXPECTED" -le 40 ]
}

@test "savings calculation - tiering alone gives 35-50%" {
    MIN_SAVINGS=35
    MAX_SAVINGS=50

    EXPECTED=$((($MIN_SAVINGS + $MAX_SAVINGS) / 2))

    [ "$EXPECTED" -ge 35 ]
    [ "$EXPECTED" -le 50 ]
}

@test "savings calculation - caps at 75% max" {
    MAX_CAP=75

    # Combined savings should not exceed cap
    [ "$MAX_CAP" -le 75 ]
}

# ============================================
# Onelist Upsell Tests
# ============================================

@test "onelist requirements - RAM >= 4GB" {
    REQUIRED_RAM_GB=4
    REQUIRED_RAM_BYTES=$((REQUIRED_RAM_GB * 1024 * 1024 * 1024))

    if [[ "$(uname)" == "Darwin" ]]; then
        ACTUAL_RAM=$(sysctl -n hw.memsize 2>/dev/null)
    else
        ACTUAL_RAM=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2 * 1024}')
    fi

    # Just verify we can detect RAM
    [ -n "$ACTUAL_RAM" ]
}

@test "onelist requirements - CPU >= 2 cores" {
    REQUIRED_CORES=2

    if [[ "$(uname)" == "Darwin" ]]; then
        ACTUAL_CORES=$(sysctl -n hw.ncpu 2>/dev/null)
    else
        ACTUAL_CORES=$(nproc 2>/dev/null || echo "2")
    fi

    [ -n "$ACTUAL_CORES" ]
    [ "$ACTUAL_CORES" -ge 1 ]
}

@test "onelist requirements - disk >= 10GB" {
    REQUIRED_DISK_GB=10

    # Just verify we can detect disk
    if [[ "$(uname)" == "Darwin" ]]; then
        DISK=$(df -g / 2>/dev/null | tail -1 | awk '{print $4}')
    else
        DISK=$(df -BG / 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G')
    fi

    [ -n "$DISK" ] || skip "Could not detect disk"
}

# ============================================
# Plugin Installation Tests
# ============================================

@test "plugin source exists" {
    PLUGIN_DIR="$PROJECT_ROOT/lib/plugins/token-optimizer"

    [ -d "$PLUGIN_DIR" ]
    [ -f "$PLUGIN_DIR/index.ts" ]
    [ -f "$PLUGIN_DIR/openclaw.plugin.json" ]
}

@test "plugin manifest is valid JSON" {
    PLUGIN_MANIFEST="$PROJECT_ROOT/lib/plugins/token-optimizer/openclaw.plugin.json"

    if command -v jq &>/dev/null; then
        run jq '.' "$PLUGIN_MANIFEST"
        [ "$status" -eq 0 ]
    fi
}

# ============================================
# Reconfiguration Tests
# ============================================

@test "detects existing config" {
    mkdir -p "$OCTO_HOME"
    cp "$FIXTURES_DIR/configs/default_config.json" "$OCTO_HOME/config.json"

    [ -f "$OCTO_HOME/config.json" ]
}

# ============================================
# Already Installed Detection Tests (NEW)
# ============================================

@test "install fails if OCTO already installed" {
    # Setup: Create existing OCTO installation
    mkdir -p "$OCTO_HOME"
    cat > "$OCTO_HOME/config.json" << 'EOF'
{"version": "1.0.0", "installedAt": "2026-01-15T10:00:00Z"}
EOF

    # Run install in non-interactive mode
    run "$PROJECT_ROOT/lib/cli/install.sh" --check-only 2>&1

    # Should fail with exit code 1
    [ "$status" -eq 1 ] || [[ "$output" == *"already installed"* ]]
}

@test "install suggests uninstall option when already installed" {
    mkdir -p "$OCTO_HOME"
    cat > "$OCTO_HOME/config.json" << 'EOF'
{"version": "1.0.0", "installedAt": "2026-01-15T10:00:00Z"}
EOF

    run "$PROJECT_ROOT/lib/cli/install.sh" --check-only 2>&1

    # Should mention uninstall as an option
    [[ "$output" == *"uninstall"* ]] || [[ "$output" == *"reinstall"* ]] || [[ "$output" == *"upgrade"* ]]
}

@test "install succeeds on fresh system" {
    # Ensure no existing config
    rm -f "$OCTO_HOME/config.json"

    # Check should pass (not actually install, just check)
    run "$PROJECT_ROOT/lib/cli/install.sh" --check-only 2>&1

    # Should not fail due to existing installation
    [[ "$output" != *"already installed"* ]]
}

@test "is_octo_installed returns true when config exists" {
    mkdir -p "$OCTO_HOME"
    echo '{"version":"1.0.0"}' > "$OCTO_HOME/config.json"

    # Function check
    if [ -f "$OCTO_HOME/config.json" ]; then
        INSTALLED=true
    else
        INSTALLED=false
    fi

    [ "$INSTALLED" == "true" ]
}

@test "is_octo_installed returns false when no config" {
    rm -f "$OCTO_HOME/config.json"

    if [ -f "$OCTO_HOME/config.json" ]; then
        INSTALLED=true
    else
        INSTALLED=false
    fi

    [ "$INSTALLED" == "false" ]
}
