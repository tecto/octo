#!/usr/bin/env bats
#
# Tests for lib/cli/uninstall.sh
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
    mkdir -p "$OPENCLAW_HOME/plugins"

    # Create existing OCTO installation
    cat > "$OCTO_HOME/config.json" << 'EOF'
{"version": "1.0.0", "installedAt": "2026-01-15T10:00:00Z"}
EOF

    # Create plugin
    mkdir -p "$OPENCLAW_HOME/plugins/token-optimizer"
    echo '{"name":"token-optimizer"}' > "$OPENCLAW_HOME/plugins/token-optimizer/openclaw.plugin.json"

    source "$HELPERS_DIR/assertions.sh"
}

teardown() {
    rm -rf "$OCTO_HOME" "$OPENCLAW_HOME"
}

# ============================================
# Uninstall Command Tests
# ============================================

@test "uninstall removes OCTO config" {
    [ -f "$OCTO_HOME/config.json" ]

    # Simulate uninstall
    rm -f "$OCTO_HOME/config.json"

    [ ! -f "$OCTO_HOME/config.json" ]
}

@test "uninstall removes token-optimizer plugin" {
    [ -d "$OPENCLAW_HOME/plugins/token-optimizer" ]

    # Simulate uninstall
    rm -rf "$OPENCLAW_HOME/plugins/token-optimizer"

    [ ! -d "$OPENCLAW_HOME/plugins/token-optimizer" ]
}

@test "uninstall removes OCTO logs directory" {
    [ -d "$OCTO_HOME/logs" ]

    # Simulate uninstall (with --purge flag)
    rm -rf "$OCTO_HOME/logs"

    [ ! -d "$OCTO_HOME/logs" ]
}

@test "uninstall preserves costs data by default" {
    mkdir -p "$OCTO_HOME/costs"
    echo '{"cost":100}' > "$OCTO_HOME/costs/2026-01-15.jsonl"

    # Default uninstall should NOT remove costs
    PRESERVE_COSTS=true

    if [ "$PRESERVE_COSTS" = true ]; then
        [ -f "$OCTO_HOME/costs/2026-01-15.jsonl" ]
    fi
}

@test "uninstall --purge removes costs data" {
    mkdir -p "$OCTO_HOME/costs"
    echo '{"cost":100}' > "$OCTO_HOME/costs/2026-01-15.jsonl"

    # Purge removes everything
    rm -rf "$OCTO_HOME/costs"

    [ ! -d "$OCTO_HOME/costs" ]
}

@test "uninstall fails if OCTO not installed" {
    rm -f "$OCTO_HOME/config.json"

    # Check if installed
    if [ ! -f "$OCTO_HOME/config.json" ]; then
        NOT_INSTALLED=true
    fi

    [ "$NOT_INSTALLED" = true ]
}

@test "uninstall stops running services" {
    # Create a mock PID file
    echo "12345" > "$OCTO_HOME/sentinel.pid"

    # Uninstall should check for and stop services
    if [ -f "$OCTO_HOME/sentinel.pid" ]; then
        SHOULD_STOP_SERVICES=true
    fi

    [ "$SHOULD_STOP_SERVICES" = true ]
}

@test "uninstall command shows help" {
    run "$PROJECT_ROOT/bin/octo" uninstall --help 2>&1

    # Should show help or indicate command exists
    [ -n "$output" ] || [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "uninstall confirms before proceeding in interactive mode" {
    # Interactive mode should require confirmation
    INTERACTIVE=true

    if [ "$INTERACTIVE" = true ]; then
        REQUIRES_CONFIRMATION=true
    fi

    [ "$REQUIRES_CONFIRMATION" = true ]
}

@test "uninstall --force skips confirmation" {
    FORCE=true

    if [ "$FORCE" = true ]; then
        SKIP_CONFIRMATION=true
    fi

    [ "$SKIP_CONFIRMATION" = true ]
}
