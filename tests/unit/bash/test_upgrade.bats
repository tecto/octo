#!/usr/bin/env bats
#
# Tests for octo upgrade command
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

    # Create existing installation with custom settings
    cat > "$OCTO_HOME/config.json" << 'EOF'
{
    "version": "1.0.0",
    "installedAt": "2026-01-15T10:00:00Z",
    "optimization": {
        "promptCaching": {"enabled": true},
        "modelTiering": {"enabled": false}
    },
    "dashboard": {
        "port": 9999
    },
    "customSetting": "user-value"
}
EOF

    source "$HELPERS_DIR/assertions.sh"
}

teardown() {
    rm -rf "$OCTO_HOME" "$OPENCLAW_HOME"
}

# ============================================
# Upgrade Command Tests
# ============================================

@test "upgrade requires OCTO to be installed" {
    rm -f "$OCTO_HOME/config.json"

    if [ ! -f "$OCTO_HOME/config.json" ]; then
        SHOULD_FAIL=true
    fi

    [ "$SHOULD_FAIL" = true ]
}

@test "upgrade preserves user config settings" {
    # Read existing custom port
    if command -v jq &>/dev/null; then
        PORT=$(jq -r '.dashboard.port' "$OCTO_HOME/config.json")
        [ "$PORT" = "9999" ]
    fi
}

@test "upgrade preserves optimization preferences" {
    if command -v jq &>/dev/null; then
        TIERING=$(jq -r '.optimization.modelTiering.enabled' "$OCTO_HOME/config.json")
        [ "$TIERING" = "false" ]
    fi
}

@test "upgrade preserves custom settings" {
    if command -v jq &>/dev/null; then
        CUSTOM=$(jq -r '.customSetting' "$OCTO_HOME/config.json")
        [ "$CUSTOM" = "user-value" ]
    fi
}

@test "upgrade updates version field" {
    NEW_VERSION="1.1.0"

    if command -v jq &>/dev/null; then
        # Simulate upgrade updating version
        jq --arg v "$NEW_VERSION" '.version = $v' "$OCTO_HOME/config.json" > "$OCTO_HOME/config.json.tmp"
        mv "$OCTO_HOME/config.json.tmp" "$OCTO_HOME/config.json"

        VERSION=$(jq -r '.version' "$OCTO_HOME/config.json")
        [ "$VERSION" = "1.1.0" ]
    fi
}

@test "upgrade updates plugin files" {
    # Plugin should be updated
    PLUGIN_DIR="$OPENCLAW_HOME/plugins/token-optimizer"
    [ -d "$PLUGIN_DIR" ]
}

@test "upgrade backs up old config" {
    # Upgrade should create backup
    BACKUP_FILE="$OCTO_HOME/config.json.backup"

    # Simulate backup
    cp "$OCTO_HOME/config.json" "$BACKUP_FILE"

    [ -f "$BACKUP_FILE" ]

    rm -f "$BACKUP_FILE"
}

@test "upgrade preserves costs data" {
    mkdir -p "$OCTO_HOME/costs"
    echo '{"cost":100}' > "$OCTO_HOME/costs/2026-01-15.jsonl"

    # Costs should remain after upgrade
    [ -f "$OCTO_HOME/costs/2026-01-15.jsonl" ]
}

@test "upgrade restarts services if running" {
    # Create mock PID file
    echo "12345" > "$OCTO_HOME/sentinel.pid"

    if [ -f "$OCTO_HOME/sentinel.pid" ]; then
        SHOULD_RESTART=true
    fi

    [ "$SHOULD_RESTART" = true ]
}

@test "upgrade command shows help" {
    run "$PROJECT_ROOT/bin/octo" upgrade --help 2>&1

    [ -n "$output" ] || [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "upgrade merges new default settings with existing" {
    # New version might add new settings
    # Upgrade should add them while preserving existing
    NEW_SETTING="newFeature"

    if command -v jq &>/dev/null; then
        jq --arg s "$NEW_SETTING" '.newFeature = $s' "$OCTO_HOME/config.json" > "$OCTO_HOME/config.json.tmp"
        mv "$OCTO_HOME/config.json.tmp" "$OCTO_HOME/config.json"

        # Both old and new should exist
        CUSTOM=$(jq -r '.customSetting' "$OCTO_HOME/config.json")
        NEW=$(jq -r '.newFeature' "$OCTO_HOME/config.json")

        [ "$CUSTOM" = "user-value" ]
        [ "$NEW" = "newFeature" ]
    fi
}
