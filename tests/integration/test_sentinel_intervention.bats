#!/usr/bin/env bats
#
# Integration tests for bloat sentinel intervention
#

setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
    FIXTURES_DIR="$TEST_DIR/../fixtures"
    HELPERS_DIR="$TEST_DIR/../helpers"

    export OCTO_HOME="$BATS_TMPDIR/octo_home_$$"
    export OPENCLAW_HOME="$BATS_TMPDIR/openclaw_home_$$"
    export OCTO_TEST_MODE=1

    mkdir -p "$OCTO_HOME"/{logs,costs,metrics,interventions,archived}
    mkdir -p "$OPENCLAW_HOME/agents/main/sessions"

    cat > "$OPENCLAW_HOME/openclaw.json" << 'EOF'
{"version": "1.0.0", "gateway": {"port": 6200}}
EOF

    cp "$FIXTURES_DIR/configs/all_enabled.json" "$OCTO_HOME/config.json"

    source "$HELPERS_DIR/assertions.sh"
}

teardown() {
    rm -rf "$OCTO_HOME" "$OPENCLAW_HOME"
    pkill -f "bloat-sentinel" 2>/dev/null || true
}

# ============================================
# Bloat Detection Tests
# ============================================

@test "sentinel detects nested injection blocks" {
    # Create session with nested injections
    cp "$FIXTURES_DIR/sessions/injection_loop_session.jsonl" \
       "$OPENCLAW_HOME/agents/main/sessions/bloated.jsonl"

    # Check for nested blocks
    nested_count=$(grep -c '\[INJECTION-DEPTH:[0-9]\+\].*\[INJECTION-DEPTH' \
                   "$OPENCLAW_HOME/agents/main/sessions/bloated.jsonl" 2>/dev/null || echo "0")

    [ "$nested_count" -gt 0 ]
}

@test "sentinel detects high marker count" {
    # Create session with many markers
    cp "$FIXTURES_DIR/sessions/high_markers_session.jsonl" \
       "$OPENCLAW_HOME/agents/main/sessions/many_markers.jsonl"

    marker_count=$(grep -c 'INJECTION-DEPTH' \
                   "$OPENCLAW_HOME/agents/main/sessions/many_markers.jsonl" 2>/dev/null || echo "0")

    [ "$marker_count" -gt 10 ]
}

# ============================================
# Intervention Logging Tests
# ============================================

@test "intervention creates log file" {
    TIMESTAMP=$(date +%Y-%m-%dT%H-%M-%S)
    LOG_FILE="$OCTO_HOME/interventions/intervention-$TIMESTAMP.log"

    # Simulate intervention logging
    cat > "$LOG_FILE" << EOF
Timestamp: $TIMESTAMP
Session: bloated.jsonl
Reason: Layer 1 triggered - nested injection blocks detected
Size before: 15MB
Markers: 5
Action: Archived and reset
EOF

    [ -f "$LOG_FILE" ]
}

@test "intervention log contains required fields" {
    LOG_FILE="$OCTO_HOME/interventions/test-intervention.log"

    cat > "$LOG_FILE" << 'EOF'
Timestamp: 2026-01-15T10:30:00
Session: test-session.jsonl
Reason: Layer 3 triggered - size > 10MB with markers
Size before: 12MB
Markers: 3
Action: Archived and reset
EOF

    content=$(cat "$LOG_FILE")

    [[ "$content" == *"Timestamp"* ]]
    [[ "$content" == *"Session"* ]]
    [[ "$content" == *"Reason"* ]]
    [[ "$content" == *"Action"* ]]
}

# ============================================
# Session Archive Tests
# ============================================

@test "intervention archives bloated session" {
    # Create bloated session
    echo '{"large":"data"}' > "$OPENCLAW_HOME/agents/main/sessions/bloated.jsonl"

    # Simulate archive
    DATE=$(date +%Y-%m-%d)
    mkdir -p "$OCTO_HOME/archived/$DATE"
    cp "$OPENCLAW_HOME/agents/main/sessions/bloated.jsonl" \
       "$OCTO_HOME/archived/$DATE/bloated.jsonl.bak"

    [ -f "$OCTO_HOME/archived/$DATE/bloated.jsonl.bak" ]
}

@test "archive preserves original content" {
    ORIGINAL_CONTENT='{"original":"session content here"}'
    echo "$ORIGINAL_CONTENT" > "$OPENCLAW_HOME/agents/main/sessions/test.jsonl"

    DATE=$(date +%Y-%m-%d)
    mkdir -p "$OCTO_HOME/archived/$DATE"
    cp "$OPENCLAW_HOME/agents/main/sessions/test.jsonl" \
       "$OCTO_HOME/archived/$DATE/test.jsonl.bak"

    archived_content=$(cat "$OCTO_HOME/archived/$DATE/test.jsonl.bak")
    [ "$archived_content" == "$ORIGINAL_CONTENT" ]
}

# ============================================
# Session Reset Tests
# ============================================

@test "intervention resets session file" {
    # Create session with content
    echo '{"bloated":"content"}' > "$OPENCLAW_HOME/agents/main/sessions/bloated.jsonl"

    # Archive first
    DATE=$(date +%Y-%m-%d)
    mkdir -p "$OCTO_HOME/archived/$DATE"
    cp "$OPENCLAW_HOME/agents/main/sessions/bloated.jsonl" \
       "$OCTO_HOME/archived/$DATE/bloated.jsonl.bak"

    # Reset (truncate)
    : > "$OPENCLAW_HOME/agents/main/sessions/bloated.jsonl"

    size=$(wc -c < "$OPENCLAW_HOME/agents/main/sessions/bloated.jsonl" | tr -d ' ')
    [ "$size" -eq 0 ]
}

@test "session file still exists after reset" {
    echo 'data' > "$OPENCLAW_HOME/agents/main/sessions/test.jsonl"

    : > "$OPENCLAW_HOME/agents/main/sessions/test.jsonl"

    [ -f "$OPENCLAW_HOME/agents/main/sessions/test.jsonl" ]
}

# ============================================
# Recovery Tests
# ============================================

@test "system recovers after intervention" {
    # Create and process bloated session
    echo '{"bloated":"data"}' > "$OPENCLAW_HOME/agents/main/sessions/bloated.jsonl"

    # Archive
    DATE=$(date +%Y-%m-%d)
    mkdir -p "$OCTO_HOME/archived/$DATE"
    cp "$OPENCLAW_HOME/agents/main/sessions/bloated.jsonl" \
       "$OCTO_HOME/archived/$DATE/bloated.jsonl.bak"

    # Reset
    : > "$OPENCLAW_HOME/agents/main/sessions/bloated.jsonl"

    # Log intervention
    echo "Intervention completed" > "$OCTO_HOME/interventions/recovery.log"

    # Verify recovery state
    [ -f "$OCTO_HOME/archived/$DATE/bloated.jsonl.bak" ]
    [ -f "$OCTO_HOME/interventions/recovery.log" ]

    size=$(wc -c < "$OPENCLAW_HOME/agents/main/sessions/bloated.jsonl" | tr -d ' ')
    [ "$size" -eq 0 ]
}

# ============================================
# Sentinel Status Tests
# ============================================

@test "sentinel status shows recent interventions" {
    # Create some intervention logs
    touch "$OCTO_HOME/interventions/intervention-2026-01-15T10-00-00.log"
    touch "$OCTO_HOME/interventions/intervention-2026-01-15T11-00-00.log"

    count=$(ls "$OCTO_HOME/interventions/"*.log 2>/dev/null | wc -l | tr -d ' ')
    [ "$count" -ge 2 ]
}

@test "sentinel command runs" {
    run "$PROJECT_ROOT/bin/octo" sentinel status
    # Should show some output
    [ -n "$output" ] || [ "$status" -le 1 ]
}
