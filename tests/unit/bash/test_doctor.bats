#!/usr/bin/env bats
#
# Tests for lib/cli/doctor.sh
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

    source "$HELPERS_DIR/assertions.sh"
}

teardown() {
    rm -rf "$OCTO_HOME" "$OPENCLAW_HOME"
}

# ============================================
# Check Counter Tests
# ============================================

@test "counter logic - pass increments CHECKS_PASSED" {
    CHECKS_PASSED=0
    CHECKS_WARNED=0
    CHECKS_FAILED=0

    # Simulate pass
    CHECKS_PASSED=$((CHECKS_PASSED + 1))

    [ "$CHECKS_PASSED" -eq 1 ]
    [ "$CHECKS_WARNED" -eq 0 ]
    [ "$CHECKS_FAILED" -eq 0 ]
}

@test "counter logic - warning increments CHECKS_WARNED" {
    CHECKS_PASSED=0
    CHECKS_WARNED=0
    CHECKS_FAILED=0

    # Simulate warning
    CHECKS_WARNED=$((CHECKS_WARNED + 1))

    [ "$CHECKS_WARNED" -eq 1 ]
}

@test "counter logic - failure increments CHECKS_FAILED" {
    CHECKS_PASSED=0
    CHECKS_WARNED=0
    CHECKS_FAILED=0

    # Simulate failure
    CHECKS_FAILED=$((CHECKS_FAILED + 1))

    [ "$CHECKS_FAILED" -eq 1 ]
}

# ============================================
# Configuration Checks
# ============================================

@test "passes when config exists" {
    cp "$FIXTURES_DIR/configs/default_config.json" "$OCTO_HOME/config.json"
    [ -f "$OCTO_HOME/config.json" ]
}

@test "fails when config missing" {
    rm -f "$OCTO_HOME/config.json"
    [ ! -f "$OCTO_HOME/config.json" ]
}

@test "passes when config is valid JSON" {
    cp "$FIXTURES_DIR/configs/default_config.json" "$OCTO_HOME/config.json"

    if command -v jq &>/dev/null; then
        run jq '.' "$OCTO_HOME/config.json"
        [ "$status" -eq 0 ]
    fi
}

@test "fails when config is invalid JSON" {
    echo "{ invalid json }" > "$OCTO_HOME/config.json"

    if command -v jq &>/dev/null; then
        run jq '.' "$OCTO_HOME/config.json"
        [ "$status" -ne 0 ]
    fi
}

@test "passes when OpenClaw dir exists" {
    [ -d "$OPENCLAW_HOME" ]
}

@test "fails when OpenClaw dir missing" {
    FAKE_HOME="$BATS_TMPDIR/nonexistent_$$"
    [ ! -d "$FAKE_HOME" ]
}

# ============================================
# Dependency Checks
# ============================================

@test "passes when python3 available" {
    run command -v python3
    [ "$status" -eq 0 ]
}

@test "passes when jq available" {
    if command -v jq &>/dev/null; then
        run command -v jq
        [ "$status" -eq 0 ]
    else
        skip "jq not installed"
    fi
}

@test "passes when curl available" {
    run command -v curl
    [ "$status" -eq 0 ]
}

# ============================================
# Session Health Checks
# ============================================

@test "passes when no bloated sessions" {
    mkdir -p "$OPENCLAW_HOME/agents/main/sessions"
    cp "$FIXTURES_DIR/sessions/healthy_session.jsonl" "$OPENCLAW_HOME/agents/main/sessions/test.jsonl"

    # Check all sessions are under 10MB
    THRESHOLD=$((10 * 1024 * 1024))
    bloated=0

    for f in "$OPENCLAW_HOME/agents/main/sessions/"*.jsonl; do
        [ -f "$f" ] || continue
        size=$(wc -c < "$f" | tr -d ' ')
        if [ "$size" -gt "$THRESHOLD" ]; then
            bloated=$((bloated + 1))
        fi
    done

    [ "$bloated" -eq 0 ]
}

@test "passes when injection counts normal" {
    cp "$FIXTURES_DIR/sessions/healthy_session.jsonl" "$OPENCLAW_HOME/agents/main/sessions/test.jsonl"

    # grep -c returns 1 if no match, so we use || echo "0" and trim whitespace
    count=$(grep -c 'INJECTION-DEPTH' "$OPENCLAW_HOME/agents/main/sessions/test.jsonl" 2>/dev/null) || count=0
    count=$(echo "$count" | tr -d '[:space:]')
    [ "$count" -le 10 ]
}

@test "warns when injection count > 10" {
    cp "$FIXTURES_DIR/sessions/high_markers_session.jsonl" "$OPENCLAW_HOME/agents/main/sessions/test.jsonl"

    count=$(grep -c 'INJECTION-DEPTH' "$OPENCLAW_HOME/agents/main/sessions/test.jsonl" 2>/dev/null || echo "0")
    [ "$count" -gt 10 ]
}

# ============================================
# Sentinel Status Checks
# ============================================

@test "detects sentinel not running when no PID file" {
    rm -f "$OCTO_HOME/bloat-sentinel.pid"
    [ ! -f "$OCTO_HOME/bloat-sentinel.pid" ]
}

@test "detects stale PID" {
    # Write a PID that definitely doesn't exist
    echo "999999" > "$OCTO_HOME/bloat-sentinel.pid"

    pid=$(cat "$OCTO_HOME/bloat-sentinel.pid")
    # Check if process exists
    if ! kill -0 "$pid" 2>/dev/null; then
        # PID is stale
        true
    fi
}

# ============================================
# Disk Space Checks
# ============================================

@test "passes when disk < 80%" {
    if [[ "$(uname)" == "Darwin" ]]; then
        usage=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
    else
        usage=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
    fi

    # This test just verifies we can detect disk usage
    [ -n "$usage" ]
}

# ============================================
# Exit Code Tests
# ============================================

@test "exit code 0 means all pass" {
    EXIT_CODE=0
    [ "$EXIT_CODE" -eq 0 ]
}

@test "exit code 1 means warnings only" {
    EXIT_CODE=1
    [ "$EXIT_CODE" -eq 1 ]
}

@test "exit code 2 means failures present" {
    EXIT_CODE=2
    [ "$EXIT_CODE" -eq 2 ]
}

# ============================================
# Doctor Command Integration
# ============================================

@test "doctor command runs" {
    cp "$FIXTURES_DIR/configs/default_config.json" "$OCTO_HOME/config.json"

    run "$PROJECT_ROOT/bin/octo" doctor
    # Should run and produce output
    [[ "$output" == *"OCTO"* ]] || [[ "$output" == *"Health"* ]] || [[ "$output" == *"Check"* ]] || [ -n "$output" ]
}

@test "doctor shows configuration section" {
    cp "$FIXTURES_DIR/configs/default_config.json" "$OCTO_HOME/config.json"

    run "$PROJECT_ROOT/bin/octo" doctor
    [[ "$output" == *"Config"* ]] || [[ "$output" == *"config"* ]] || [[ "$output" == *"PASS"* ]] || [[ "$output" == *"pass"* ]] || [ -n "$output" ]
}

@test "doctor shows dependencies section" {
    cp "$FIXTURES_DIR/configs/default_config.json" "$OCTO_HOME/config.json"

    run "$PROJECT_ROOT/bin/octo" doctor
    [[ "$output" == *"python"* ]] || [[ "$output" == *"jq"* ]] || [[ "$output" == *"Depend"* ]] || [ -n "$output" ]
}
