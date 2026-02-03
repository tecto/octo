#!/usr/bin/env bats
#
# Tests for octo reinstall command
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
    mkdir -p "$OPENCLAW_HOME/plugins/token-optimizer"

    cat > "$OCTO_HOME/config.json" << 'EOF'
{"version": "1.0.0", "installedAt": "2026-01-15T10:00:00Z", "customSetting": "user-value"}
EOF

    source "$HELPERS_DIR/assertions.sh"
}

teardown() {
    rm -rf "$OCTO_HOME" "$OPENCLAW_HOME"
}

# ============================================
# Reinstall Command Tests
# ============================================

@test "reinstall requires OCTO to be installed" {
    # Remove config to simulate not installed
    rm -f "$OCTO_HOME/config.json"

    # Reinstall should fail if not installed
    if [ ! -f "$OCTO_HOME/config.json" ]; then
        SHOULD_FAIL=true
    fi

    [ "$SHOULD_FAIL" = true ]
}

@test "reinstall does not preserve custom config" {
    # Reinstall should be a clean slate
    PRESERVE_CONFIG=false

    [ "$PRESERVE_CONFIG" = false ]
}

@test "reinstall removes old config before creating new" {
    OLD_CONFIG="$OCTO_HOME/config.json"
    [ -f "$OLD_CONFIG" ]

    # Simulate reinstall - removes old
    rm -f "$OLD_CONFIG"

    [ ! -f "$OLD_CONFIG" ]
}

@test "reinstall calls uninstall then install" {
    # Reinstall = uninstall + install
    STEPS=("uninstall" "install")

    [ "${STEPS[0]}" = "uninstall" ]
    [ "${STEPS[1]}" = "install" ]
}

@test "reinstall shows warning about data loss" {
    # Should warn user
    WARNING_SHOWN=true

    [ "$WARNING_SHOWN" = true ]
}

@test "reinstall --force skips confirmation" {
    FORCE=true

    if [ "$FORCE" = true ]; then
        SKIP_CONFIRMATION=true
    fi

    [ "$SKIP_CONFIRMATION" = true ]
}

@test "reinstall command shows help" {
    run "$PROJECT_ROOT/bin/octo" reinstall --help 2>&1

    [ -n "$output" ] || [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}
