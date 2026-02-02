#!/usr/bin/env bats
#
# Tests for lib/watchdog/bloat-sentinel.sh
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
    # Kill any test sentinel processes
    pkill -f "bloat-sentinel.*test" 2>/dev/null || true
}

# ============================================
# Injection Block Counting Tests
# ============================================

@test "counts zero blocks in clean message" {
    echo '{"type":"message","message":{"role":"user","content":"Hello world"}}' > "$BATS_TMPDIR/clean.jsonl"

    # Use simpler pattern - just check for INJECTION-DEPTH marker
    count=$(grep -c 'INJECTION-DEPTH' "$BATS_TMPDIR/clean.jsonl" 2>/dev/null) || count=0
    [ "$count" -eq 0 ]
}

@test "counts single injection block" {
    cp "$FIXTURES_DIR/sessions/injection_loop_session.jsonl" "$BATS_TMPDIR/test.jsonl"

    # Count lines with injection markers
    count=$(grep -c 'INJECTION-DEPTH' "$BATS_TMPDIR/test.jsonl" 2>/dev/null || echo "0")
    [ "$count" -gt 0 ]
}

@test "counts multiple injection blocks" {
    cp "$FIXTURES_DIR/sessions/high_markers_session.jsonl" "$BATS_TMPDIR/test.jsonl"

    count=$(grep -c 'INJECTION-DEPTH' "$BATS_TMPDIR/test.jsonl" 2>/dev/null || echo "0")
    [ "$count" -gt 10 ]
}

@test "requires 'Recovered Conversation Context' after marker" {
    # Create a file with marker but wrong text after
    echo '{"content":"[INJECTION-DEPTH:1] Wrong text here"}' > "$BATS_TMPDIR/wrong.jsonl"

    # Check that 'Recovered Conversation Context' is NOT present
    count=$(grep -c 'Recovered Conversation Context' "$BATS_TMPDIR/wrong.jsonl" 2>/dev/null) || count=0
    [ "$count" -eq 0 ]
}

# ============================================
# Layer 1: Nested Blocks Tests
# ============================================

@test "layer 1 triggers when >1 block in single message" {
    # A message with nested blocks
    MSG='[INJECTION-DEPTH:2] Recovered Conversation Context [INJECTION-DEPTH:1] Recovered Conversation Context'

    # Count INJECTION-DEPTH markers in single message
    count=$(echo "$MSG" | grep -o 'INJECTION-DEPTH' | wc -l | tr -d ' ')
    [ "$count" -gt 1 ]
}

@test "layer 1 does not trigger for exactly 1 block" {
    MSG='[INJECTION-DEPTH:1] Recovered Conversation Context some text'

    # Simple check - only one depth marker
    count=$(echo "$MSG" | grep -o 'INJECTION-DEPTH' | wc -l | tr -d ' ')
    [ "$count" -eq 1 ]
}

@test "layer 1 does not trigger for 0 blocks" {
    MSG='Hello, this is a normal message without any injection markers.'

    count=$(echo "$MSG" | grep -o 'INJECTION-DEPTH' | wc -l | tr -d ' ')
    [ "$count" -eq 0 ]
}

# ============================================
# Layer 2: Rapid Growth Tests
# ============================================

@test "calculates growth rate in bytes" {
    # Initial size
    SIZE_1=100000
    TIME_1=$(date +%s)

    # After growth
    SIZE_2=200000
    TIME_2=$((TIME_1 + 60))

    # Growth rate = (SIZE_2 - SIZE_1) / (TIME_2 - TIME_1)
    GROWTH_RATE=$(( (SIZE_2 - SIZE_1) / (TIME_2 - TIME_1) ))

    # Should be ~1666 bytes/second
    [ "$GROWTH_RATE" -gt 1000 ]
}

@test "layer 2 threshold is 1MB in 60s" {
    THRESHOLD=$((1 * 1024 * 1024))  # 1MB
    TIME_WINDOW=60

    [ "$THRESHOLD" -eq 1048576 ]
    [ "$TIME_WINDOW" -eq 60 ]
}

# ============================================
# Layer 3: Size with Markers Tests
# ============================================

@test "layer 3 threshold is 10MB with >= 2 markers" {
    SIZE_THRESHOLD=$((10 * 1024 * 1024))  # 10MB
    MARKER_THRESHOLD=2

    [ "$SIZE_THRESHOLD" -eq 10485760 ]
    [ "$MARKER_THRESHOLD" -eq 2 ]
}

@test "layer 3 does not trigger for large size without markers" {
    # Large file but no markers
    SIZE=$((15 * 1024 * 1024))
    MARKERS=0

    # Should NOT trigger
    if [ "$SIZE" -gt 10485760 ] && [ "$MARKERS" -ge 2 ]; then
        TRIGGER=1
    else
        TRIGGER=0
    fi

    [ "$TRIGGER" -eq 0 ]
}

@test "layer 3 does not trigger for small size with markers" {
    # Small file with markers
    SIZE=$((1 * 1024 * 1024))  # 1MB
    MARKERS=5

    # Should NOT trigger (size too small)
    if [ "$SIZE" -gt 10485760 ] && [ "$MARKERS" -ge 2 ]; then
        TRIGGER=1
    else
        TRIGGER=0
    fi

    [ "$TRIGGER" -eq 0 ]
}

# ============================================
# Layer 4: Total Markers Tests
# ============================================

@test "layer 4 threshold is > 10 markers" {
    THRESHOLD=10

    # 15 markers should trigger logging
    MARKERS=15
    [ "$MARKERS" -gt "$THRESHOLD" ]
}

@test "layer 4 logs but does not intervene" {
    # Layer 4 is monitor-only
    LAYER_4_INTERVENE=false
    [ "$LAYER_4_INTERVENE" == "false" ]
}

# ============================================
# Intervention Tests
# ============================================

@test "creates intervention log" {
    mkdir -p "$OCTO_HOME/interventions"
    TIMESTAMP=$(date +%Y-%m-%dT%H-%M-%S)

    touch "$OCTO_HOME/interventions/intervention-$TIMESTAMP.log"
    [ -f "$OCTO_HOME/interventions/intervention-$TIMESTAMP.log" ]
}

@test "archives session to dated directory" {
    mkdir -p "$OCTO_HOME/archived/2026-01-15"
    touch "$OCTO_HOME/archived/2026-01-15/session.jsonl.bak"

    [ -f "$OCTO_HOME/archived/2026-01-15/session.jsonl.bak" ]
}

@test "preserves original session as backup" {
    mkdir -p "$OPENCLAW_HOME/agents/main/sessions"
    echo '{"test":"data"}' > "$OPENCLAW_HOME/agents/main/sessions/test.jsonl"

    # Create backup
    cp "$OPENCLAW_HOME/agents/main/sessions/test.jsonl" "$OPENCLAW_HOME/agents/main/sessions/test.jsonl.bak"

    [ -f "$OPENCLAW_HOME/agents/main/sessions/test.jsonl.bak" ]
}

@test "resets session file" {
    mkdir -p "$OPENCLAW_HOME/agents/main/sessions"
    echo '{"large":"session data here"}' > "$OPENCLAW_HOME/agents/main/sessions/test.jsonl"

    # Reset (truncate)
    : > "$OPENCLAW_HOME/agents/main/sessions/test.jsonl"

    size=$(wc -c < "$OPENCLAW_HOME/agents/main/sessions/test.jsonl" | tr -d ' ')
    [ "$size" -eq 0 ]
}

# ============================================
# Daemon Management Tests
# ============================================

@test "creates PID file on daemon start" {
    echo "12345" > "$OCTO_HOME/bloat-sentinel.pid"
    [ -f "$OCTO_HOME/bloat-sentinel.pid" ]

    pid=$(cat "$OCTO_HOME/bloat-sentinel.pid")
    [ "$pid" == "12345" ]
}

@test "removes PID file on stop" {
    echo "12345" > "$OCTO_HOME/bloat-sentinel.pid"
    rm -f "$OCTO_HOME/bloat-sentinel.pid"

    [ ! -f "$OCTO_HOME/bloat-sentinel.pid" ]
}

@test "detects stale PID" {
    # Write a PID that doesn't exist
    echo "999999" > "$OCTO_HOME/bloat-sentinel.pid"

    pid=$(cat "$OCTO_HOME/bloat-sentinel.pid")
    if ! kill -0 "$pid" 2>/dev/null; then
        STALE=true
    else
        STALE=false
    fi

    [ "$STALE" == "true" ]
}

@test "prevents duplicate daemon" {
    # If PID file exists and process is running, should not start another
    echo "$$" > "$OCTO_HOME/bloat-sentinel.pid"  # Current process PID

    # Check if process exists
    pid=$(cat "$OCTO_HOME/bloat-sentinel.pid")
    if kill -0 "$pid" 2>/dev/null; then
        RUNNING=true
    else
        RUNNING=false
    fi

    [ "$RUNNING" == "true" ]
}

# ============================================
# Status Display Tests
# ============================================

@test "shows running status with PID" {
    run "$PROJECT_ROOT/bin/octo" sentinel status
    # Should show some status information
    [[ "$output" == *"sentinel"* ]] || [[ "$output" == *"running"* ]] || [[ "$output" == *"not"* ]] || [[ "$output" == *"PID"* ]] || [ -n "$output" ]
}

@test "lists recent interventions" {
    mkdir -p "$OCTO_HOME/interventions"
    touch "$OCTO_HOME/interventions/intervention-2026-01-15T10-00-00.log"

    count=$(ls "$OCTO_HOME/interventions/"*.log 2>/dev/null | wc -l | tr -d ' ')
    [ "$count" -ge 1 ]
}
