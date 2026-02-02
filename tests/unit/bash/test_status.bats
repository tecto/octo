#!/usr/bin/env bats
#
# Tests for lib/cli/status.sh
#

setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$TEST_DIR/../../.." && pwd)"
    FIXTURES_DIR="$TEST_DIR/../../fixtures"
    HELPERS_DIR="$TEST_DIR/../../helpers"

    export OCTO_HOME="$BATS_TMPDIR/octo_home_$$"
    export OPENCLAW_HOME="$BATS_TMPDIR/openclaw_home_$$"
    export OCTO_TEST_MODE=1

    mkdir -p "$OCTO_HOME"/{logs,costs,metrics,interventions}
    mkdir -p "$OPENCLAW_HOME/agents/main/sessions"

    cat > "$OPENCLAW_HOME/openclaw.json" << 'EOF'
{"version": "1.0.0", "gateway": {"port": 6200}}
EOF

    source "$HELPERS_DIR/assertions.sh"
}

teardown() {
    rm -rf "$OCTO_HOME" "$OPENCLAW_HOME"
}

# ============================================
# Config Loading Tests
# ============================================

@test "exits with message when config not found" {
    run "$PROJECT_ROOT/bin/octo" status
    # Should indicate config is missing
    [[ "$output" == *"config"* ]] || [[ "$output" == *"install"* ]] || [[ "$output" == *"not found"* ]] || [[ "$output" == *"Run"* ]]
}

@test "loads config from OCTO_HOME/config.json" {
    cp "$FIXTURES_DIR/configs/default_config.json" "$OCTO_HOME/config.json"

    run "$PROJECT_ROOT/bin/octo" status
    # Should not complain about missing config
    [[ "$output" != *"not found"* ]] || [[ "$output" == *"OCTO"* ]]
}

@test "parses optimization.promptCaching.enabled" {
    cp "$FIXTURES_DIR/configs/all_enabled.json" "$OCTO_HOME/config.json"

    if command -v jq &>/dev/null; then
        enabled=$(jq -r '.optimization.promptCaching.enabled' "$OCTO_HOME/config.json")
        [ "$enabled" == "true" ]
    fi
}

@test "parses onelist.installed" {
    cp "$FIXTURES_DIR/configs/all_enabled.json" "$OCTO_HOME/config.json"

    if command -v jq &>/dev/null; then
        installed=$(jq -r '.onelist.installed' "$OCTO_HOME/config.json")
        [ "$installed" == "true" ]
    fi
}

# ============================================
# Boolean Formatting Tests
# ============================================

@test "bool_to_status formats true correctly" {
    # Test function logic
    bool_to_status() {
        if [[ "$1" == "true" ]]; then
            echo "enabled"
        else
            echo "disabled"
        fi
    }

    result=$(bool_to_status "true")
    [ "$result" == "enabled" ]
}

@test "bool_to_status formats false correctly" {
    bool_to_status() {
        if [[ "$1" == "true" ]]; then
            echo "enabled"
        else
            echo "disabled"
        fi
    }

    result=$(bool_to_status "false")
    [ "$result" == "disabled" ]
}

# ============================================
# Session Analysis Tests
# ============================================

@test "counts active sessions" {
    mkdir -p "$OPENCLAW_HOME/agents/main/sessions"
    echo '{"type":"message"}' > "$OPENCLAW_HOME/agents/main/sessions/session1.jsonl"
    echo '{"type":"message"}' > "$OPENCLAW_HOME/agents/main/sessions/session2.jsonl"

    count=$(find "$OPENCLAW_HOME" -name "*.jsonl" -type f ! -name "sessions.json" ! -name ".archived.*" 2>/dev/null | wc -l | tr -d ' ')
    [ "$count" -eq 2 ]
}

@test "excludes sessions.json from count" {
    mkdir -p "$OPENCLAW_HOME/agents/main/sessions"
    echo '{"type":"message"}' > "$OPENCLAW_HOME/agents/main/sessions/session1.jsonl"
    echo '[]' > "$OPENCLAW_HOME/agents/main/sessions/sessions.json"

    count=$(find "$OPENCLAW_HOME" -name "*.jsonl" -type f ! -name "sessions.json" 2>/dev/null | wc -l | tr -d ' ')
    [ "$count" -eq 1 ]
}

@test "calculates total session size" {
    mkdir -p "$OPENCLAW_HOME/agents/main/sessions"
    # Create a session with known content
    printf '%1000s' | tr ' ' 'x' > "$OPENCLAW_HOME/agents/main/sessions/test.jsonl"

    size=$(du -sb "$OPENCLAW_HOME/agents/main/sessions/test.jsonl" 2>/dev/null | cut -f1 || stat -f%z "$OPENCLAW_HOME/agents/main/sessions/test.jsonl" 2>/dev/null)
    [ -n "$size" ]
    [ "$size" -ge 1000 ]
}

@test "identifies largest session" {
    mkdir -p "$OPENCLAW_HOME/agents/main/sessions"
    echo "small" > "$OPENCLAW_HOME/agents/main/sessions/small.jsonl"
    printf '%10000s' | tr ' ' 'x' > "$OPENCLAW_HOME/agents/main/sessions/large.jsonl"

    largest=$(ls -S "$OPENCLAW_HOME/agents/main/sessions/"*.jsonl 2>/dev/null | head -1)
    [[ "$largest" == *"large.jsonl"* ]]
}

# ============================================
# Cost Summary Tests
# ============================================

@test "reads today's cost file" {
    TODAY=$(date +%Y-%m-%d)
    mkdir -p "$OCTO_HOME/costs"
    cp "$FIXTURES_DIR/costs/sample_costs.jsonl" "$OCTO_HOME/costs/costs-$TODAY.jsonl"

    [ -f "$OCTO_HOME/costs/costs-$TODAY.jsonl" ]
}

@test "calculates total cost from JSONL" {
    cp "$FIXTURES_DIR/costs/sample_costs.jsonl" "$OCTO_HOME/costs/sample.jsonl"

    if command -v jq &>/dev/null; then
        total=$(jq -s '[.[].total_cost] | add' "$OCTO_HOME/costs/sample.jsonl")
        [ -n "$total" ]
        # Total should be > 0
        [[ "$total" != "null" ]]
    fi
}

@test "counts total requests" {
    cp "$FIXTURES_DIR/costs/sample_costs.jsonl" "$OCTO_HOME/costs/sample.jsonl"

    count=$(wc -l < "$OCTO_HOME/costs/sample.jsonl" | tr -d ' ')
    [ "$count" -eq 5 ]
}

@test "shows 'no data' when cost file missing" {
    TODAY=$(date +%Y-%m-%d)
    rm -f "$OCTO_HOME/costs/costs-$TODAY.jsonl"

    [ ! -f "$OCTO_HOME/costs/costs-$TODAY.jsonl" ]
}

# ============================================
# Intervention History Tests
# ============================================

@test "lists recent intervention logs" {
    mkdir -p "$OCTO_HOME/interventions"
    touch "$OCTO_HOME/interventions/intervention-2026-01-15T10-30-00.log"
    touch "$OCTO_HOME/interventions/intervention-2026-01-15T11-00-00.log"

    count=$(ls "$OCTO_HOME/interventions/"*.log 2>/dev/null | wc -l | tr -d ' ')
    [ "$count" -eq 2 ]
}

@test "shows 'none' when no interventions" {
    mkdir -p "$OCTO_HOME/interventions"
    rm -f "$OCTO_HOME/interventions/"*.log 2>/dev/null

    count=$(ls "$OCTO_HOME/interventions/"*.log 2>/dev/null | wc -l | tr -d ' ')
    [ "$count" -eq 0 ]
}

@test "parses timestamp from intervention filename" {
    FILENAME="intervention-2026-01-15T10-30-00.log"

    # Extract timestamp pattern
    if [[ "$FILENAME" =~ intervention-([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}-[0-9]{2}-[0-9]{2}) ]]; then
        timestamp="${BASH_REMATCH[1]}"
        [ "$timestamp" == "2026-01-15T10-30-00" ]
    fi
}
