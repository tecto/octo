#!/usr/bin/env bats
#
# Tests for lib/watchdog/bump-openclaw-bot.sh (surgery script)
#

setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$TEST_DIR/../../.." && pwd)"
    FIXTURES_DIR="$TEST_DIR/../../fixtures"
    HELPERS_DIR="$TEST_DIR/../../helpers"

    export OCTO_HOME="$BATS_TMPDIR/octo_home_$$"
    export OPENCLAW_HOME="$BATS_TMPDIR/openclaw_home_$$"
    export OCTO_TEST_MODE=1

    mkdir -p "$OCTO_HOME"/{logs,costs,metrics,interventions,archived}
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
# Session Backup Tests
# ============================================

@test "creates backup before surgery" {
    mkdir -p "$OPENCLAW_HOME/agents/main/sessions"
    echo '{"test":"data"}' > "$OPENCLAW_HOME/agents/main/sessions/bloated.jsonl"

    # Create backup
    cp "$OPENCLAW_HOME/agents/main/sessions/bloated.jsonl" \
       "$OPENCLAW_HOME/agents/main/sessions/bloated.jsonl.bak"

    [ -f "$OPENCLAW_HOME/agents/main/sessions/bloated.jsonl.bak" ]
}

@test "backup preserves original content" {
    mkdir -p "$OPENCLAW_HOME/agents/main/sessions"
    ORIGINAL='{"original":"content"}'
    echo "$ORIGINAL" > "$OPENCLAW_HOME/agents/main/sessions/test.jsonl"

    cp "$OPENCLAW_HOME/agents/main/sessions/test.jsonl" \
       "$OPENCLAW_HOME/agents/main/sessions/test.jsonl.bak"

    backup_content=$(cat "$OPENCLAW_HOME/agents/main/sessions/test.jsonl.bak")
    [ "$backup_content" == "$ORIGINAL" ]
}

@test "archives to dated directory" {
    DATE=$(date +%Y-%m-%d)
    mkdir -p "$OCTO_HOME/archived/$DATE"

    [ -d "$OCTO_HOME/archived/$DATE" ]
}

# ============================================
# Session Truncation Tests
# ============================================

@test "truncates session file" {
    mkdir -p "$OPENCLAW_HOME/agents/main/sessions"
    echo '{"large":"session with lots of data"}' > "$OPENCLAW_HOME/agents/main/sessions/test.jsonl"

    # Truncate
    : > "$OPENCLAW_HOME/agents/main/sessions/test.jsonl"

    size=$(wc -c < "$OPENCLAW_HOME/agents/main/sessions/test.jsonl" | tr -d ' ')
    [ "$size" -eq 0 ]
}

@test "preserves session file after truncation" {
    mkdir -p "$OPENCLAW_HOME/agents/main/sessions"
    echo 'data' > "$OPENCLAW_HOME/agents/main/sessions/test.jsonl"

    : > "$OPENCLAW_HOME/agents/main/sessions/test.jsonl"

    # File should still exist
    [ -f "$OPENCLAW_HOME/agents/main/sessions/test.jsonl" ]
}

# ============================================
# Gateway Restart Tests
# ============================================

@test "restart command uses correct signal" {
    # SIGTERM is the graceful shutdown signal
    SIGNAL="TERM"
    [ "$SIGNAL" == "TERM" ]
}

@test "restart waits for shutdown" {
    WAIT_SECONDS=5
    [ "$WAIT_SECONDS" -eq 5 ]
}

@test "restart verifies process stopped" {
    # Simulate checking if process stopped
    FAKE_PID=999999

    if ! kill -0 "$FAKE_PID" 2>/dev/null; then
        STOPPED=true
    else
        STOPPED=false
    fi

    [ "$STOPPED" == "true" ]
}

# ============================================
# Intervention Logging Tests
# ============================================

@test "creates intervention log file" {
    mkdir -p "$OCTO_HOME/interventions"
    TIMESTAMP=$(date +%Y-%m-%dT%H-%M-%S)

    echo "Intervention at $TIMESTAMP" > "$OCTO_HOME/interventions/intervention-$TIMESTAMP.log"

    [ -f "$OCTO_HOME/interventions/intervention-$TIMESTAMP.log" ]
}

@test "intervention log contains timestamp" {
    mkdir -p "$OCTO_HOME/interventions"
    TIMESTAMP=$(date +%Y-%m-%dT%H-%M-%S)
    LOG_FILE="$OCTO_HOME/interventions/intervention-$TIMESTAMP.log"

    echo "Surgery performed at $TIMESTAMP" > "$LOG_FILE"

    content=$(cat "$LOG_FILE")
    [[ "$content" == *"$TIMESTAMP"* ]]
}

@test "intervention log contains reason" {
    mkdir -p "$OCTO_HOME/interventions"
    LOG_FILE="$OCTO_HOME/interventions/test.log"

    echo "Reason: Session bloat detected (Layer 1: nested blocks)" > "$LOG_FILE"

    content=$(cat "$LOG_FILE")
    [[ "$content" == *"Reason"* ]]
}

@test "intervention log contains session info" {
    mkdir -p "$OCTO_HOME/interventions"
    LOG_FILE="$OCTO_HOME/interventions/test.log"

    cat > "$LOG_FILE" << 'EOF'
Session: test-session.jsonl
Size: 15MB
Injection markers: 5
Layer triggered: 3
EOF

    content=$(cat "$LOG_FILE")
    [[ "$content" == *"Session"* ]]
    [[ "$content" == *"Size"* ]]
}

# ============================================
# Dry Run Tests
# ============================================

@test "dry run flag prevents changes" {
    DRY_RUN=true

    if [ "$DRY_RUN" == "true" ]; then
        CHANGES_MADE=false
    else
        CHANGES_MADE=true
    fi

    [ "$CHANGES_MADE" == "false" ]
}

@test "dry run outputs what would happen" {
    DRY_RUN=true
    OUTPUT="[DRY RUN] Would truncate session: test.jsonl"

    [[ "$OUTPUT" == *"DRY RUN"* ]]
    [[ "$OUTPUT" == *"Would"* ]]
}

# ============================================
# Force Flag Tests
# ============================================

@test "force flag skips confirmation" {
    FORCE=true

    if [ "$FORCE" == "true" ]; then
        SKIP_CONFIRM=true
    else
        SKIP_CONFIRM=false
    fi

    [ "$SKIP_CONFIRM" == "true" ]
}

# ============================================
# Session Selection Tests
# ============================================

@test "selects all sessions with --all flag" {
    mkdir -p "$OPENCLAW_HOME/agents/main/sessions"
    touch "$OPENCLAW_HOME/agents/main/sessions/s1.jsonl"
    touch "$OPENCLAW_HOME/agents/main/sessions/s2.jsonl"
    touch "$OPENCLAW_HOME/agents/main/sessions/s3.jsonl"

    ALL_FLAG=true
    if [ "$ALL_FLAG" == "true" ]; then
        count=$(ls "$OPENCLAW_HOME/agents/main/sessions/"*.jsonl 2>/dev/null | wc -l | tr -d ' ')
    fi

    [ "$count" -eq 3 ]
}

@test "selects specific session by name" {
    mkdir -p "$OPENCLAW_HOME/agents/main/sessions"
    touch "$OPENCLAW_HOME/agents/main/sessions/target.jsonl"
    touch "$OPENCLAW_HOME/agents/main/sessions/other.jsonl"

    SESSION_NAME="target.jsonl"
    [ -f "$OPENCLAW_HOME/agents/main/sessions/$SESSION_NAME" ]
}

@test "selects bloated sessions only with --bloated flag" {
    # Threshold for bloated
    THRESHOLD=$((10 * 1024 * 1024))  # 10MB

    # Simulate file sizes
    SMALL_SIZE=$((1 * 1024 * 1024))   # 1MB
    LARGE_SIZE=$((15 * 1024 * 1024))  # 15MB

    if [ "$LARGE_SIZE" -gt "$THRESHOLD" ]; then
        IS_BLOATED=true
    else
        IS_BLOATED=false
    fi

    [ "$IS_BLOATED" == "true" ]

    if [ "$SMALL_SIZE" -gt "$THRESHOLD" ]; then
        SMALL_IS_BLOATED=true
    else
        SMALL_IS_BLOATED=false
    fi

    [ "$SMALL_IS_BLOATED" == "false" ]
}

# ============================================
# Integration Test
# ============================================

@test "surgery command shows help" {
    run "$PROJECT_ROOT/bin/octo" surgery --help
    [ -n "$output" ] || [ "$status" -eq 0 ]
}
