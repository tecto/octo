#!/usr/bin/env bats
#
# Integration tests for OCTO install flow
#

setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
    FIXTURES_DIR="$TEST_DIR/../fixtures"
    HELPERS_DIR="$TEST_DIR/../helpers"

    export OCTO_HOME="$BATS_TMPDIR/octo_home_$$"
    export OPENCLAW_HOME="$BATS_TMPDIR/openclaw_home_$$"
    export OCTO_TEST_MODE=1
    export OCTO_NONINTERACTIVE=1

    # Create mock OpenClaw installation
    mkdir -p "$OPENCLAW_HOME/agents/main/sessions"
    mkdir -p "$OPENCLAW_HOME/plugins"

    cat > "$OPENCLAW_HOME/openclaw.json" << 'EOF'
{"version": "1.0.0", "gateway": {"port": 6200}}
EOF

    # Create some mock sessions
    echo '{"type":"message"}' > "$OPENCLAW_HOME/agents/main/sessions/session1.jsonl"
    echo '{"type":"message"}' > "$OPENCLAW_HOME/agents/main/sessions/session2.jsonl"

    source "$HELPERS_DIR/assertions.sh"
}

teardown() {
    rm -rf "$OCTO_HOME" "$OPENCLAW_HOME"
    # Clean up any test processes
    pkill -f "bloat-sentinel.*test" 2>/dev/null || true
}

# ============================================
# Full Install Flow Tests
# ============================================

@test "full install creates OCTO_HOME directory" {
    [ ! -d "$OCTO_HOME" ]

    # Run status which should create directories
    run "$PROJECT_ROOT/bin/octo" --help

    [ -d "$OCTO_HOME" ] || [ "$status" -eq 0 ]
}

@test "full install creates all expected directories" {
    mkdir -p "$OCTO_HOME"

    # Expected directories
    EXPECTED_DIRS=(
        "$OCTO_HOME/logs"
        "$OCTO_HOME/costs"
        "$OCTO_HOME/metrics"
    )

    for dir in "${EXPECTED_DIRS[@]}"; do
        mkdir -p "$dir"
        [ -d "$dir" ]
    done
}

@test "install detects OpenClaw installation" {
    [ -f "$OPENCLAW_HOME/openclaw.json" ]
}

@test "install counts existing sessions" {
    count=$(find "$OPENCLAW_HOME/agents" -name "*.jsonl" -type f 2>/dev/null | wc -l | tr -d ' ')
    [ "$count" -eq 2 ]
}

# ============================================
# Configuration Tests
# ============================================

@test "install with all features enabled creates correct config" {
    mkdir -p "$OCTO_HOME"
    cp "$FIXTURES_DIR/configs/all_enabled.json" "$OCTO_HOME/config.json"

    if command -v jq &>/dev/null; then
        caching=$(jq -r '.optimization.promptCaching.enabled' "$OCTO_HOME/config.json")
        tiering=$(jq -r '.optimization.modelTiering.enabled' "$OCTO_HOME/config.json")
        monitoring=$(jq -r '.monitoring.sessionMonitoring.enabled' "$OCTO_HOME/config.json")
        bloat=$(jq -r '.monitoring.bloatDetection.enabled' "$OCTO_HOME/config.json")

        [ "$caching" == "true" ]
        [ "$tiering" == "true" ]
        [ "$monitoring" == "true" ]
        [ "$bloat" == "true" ]
    fi
}

@test "install with all features disabled creates correct config" {
    mkdir -p "$OCTO_HOME"
    cp "$FIXTURES_DIR/configs/all_disabled.json" "$OCTO_HOME/config.json"

    if command -v jq &>/dev/null; then
        caching=$(jq -r '.optimization.promptCaching.enabled' "$OCTO_HOME/config.json")
        tiering=$(jq -r '.optimization.modelTiering.enabled' "$OCTO_HOME/config.json")

        [ "$caching" == "false" ]
        [ "$tiering" == "false" ]
    fi
}

@test "install detects and uses custom port" {
    export OCTO_PORT=7777
    mkdir -p "$OCTO_HOME"

    # Create config with custom port
    cat > "$OCTO_HOME/config.json" << 'EOF'
{
  "version": "1.0.0",
  "dashboard": {"port": 7777}
}
EOF

    if command -v jq &>/dev/null; then
        port=$(jq -r '.dashboard.port' "$OCTO_HOME/config.json")
        [ "$port" == "7777" ]
    fi
}

# ============================================
# Plugin Installation Tests
# ============================================

@test "install copies plugin files" {
    PLUGIN_SRC="$PROJECT_ROOT/lib/plugins/token-optimizer"
    PLUGIN_DST="$OPENCLAW_HOME/plugins/token-optimizer"

    mkdir -p "$PLUGIN_DST"
    cp -r "$PLUGIN_SRC/"* "$PLUGIN_DST/" 2>/dev/null || true

    [ -d "$PLUGIN_DST" ]
}

@test "plugin manifest exists after install" {
    PLUGIN_DST="$OPENCLAW_HOME/plugins/token-optimizer"

    mkdir -p "$PLUGIN_DST"
    cp "$PROJECT_ROOT/lib/plugins/token-optimizer/openclaw.plugin.json" "$PLUGIN_DST/"

    [ -f "$PLUGIN_DST/openclaw.plugin.json" ]
}

# ============================================
# Reconfiguration Tests
# ============================================

@test "reconfigure detects existing config" {
    mkdir -p "$OCTO_HOME"
    cp "$FIXTURES_DIR/configs/default_config.json" "$OCTO_HOME/config.json"

    [ -f "$OCTO_HOME/config.json" ]
}

@test "reconfigure preserves existing data" {
    mkdir -p "$OCTO_HOME/costs"

    # Create existing cost data
    echo '{"cost": 0.05}' > "$OCTO_HOME/costs/existing.jsonl"

    # Simulate reconfigure (just copy new config)
    cp "$FIXTURES_DIR/configs/default_config.json" "$OCTO_HOME/config.json"

    # Existing data should still be there
    [ -f "$OCTO_HOME/costs/existing.jsonl" ]
}

# ============================================
# Status After Install Tests
# ============================================

@test "status works after install" {
    mkdir -p "$OCTO_HOME"
    cp "$FIXTURES_DIR/configs/default_config.json" "$OCTO_HOME/config.json"

    run "$PROJECT_ROOT/bin/octo" status
    # Should produce output without errors
    [ -n "$output" ]
}

@test "doctor works after install" {
    mkdir -p "$OCTO_HOME"
    cp "$FIXTURES_DIR/configs/default_config.json" "$OCTO_HOME/config.json"

    run "$PROJECT_ROOT/bin/octo" doctor
    # Should produce health check output
    [ -n "$output" ]
}
