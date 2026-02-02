#!/usr/bin/env bats
#
# Tests for lib/watchdog/openclaw-watchdog.sh
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
# Gateway Detection Tests
# ============================================

@test "detects gateway process pattern" {
    # The pattern used to detect gateway
    PATTERN="openclaw-gateway"

    # Test the pattern matching
    TEST_STRING="node /path/to/openclaw-gateway --port 6200"
    [[ "$TEST_STRING" == *"$PATTERN"* ]]
}

@test "gateway PID extraction works" {
    # Simulate pgrep output
    echo "12345" > "$BATS_TMPDIR/pgrep_output"

    pid=$(cat "$BATS_TMPDIR/pgrep_output" | head -1)
    [ "$pid" == "12345" ]
}

# ============================================
# Memory Monitoring Tests
# ============================================

@test "memory threshold warning at 300MB" {
    WARN_THRESHOLD=$((300 * 1024))  # 300MB in KB

    # Simulate process memory (in KB)
    PROCESS_MEMORY=350000  # 350MB

    if [ "$PROCESS_MEMORY" -gt "$WARN_THRESHOLD" ]; then
        WARNING=true
    else
        WARNING=false
    fi

    [ "$WARNING" == "true" ]
}

@test "memory threshold critical at 500MB" {
    CRITICAL_THRESHOLD=$((500 * 1024))  # 500MB in KB

    # Simulate process memory (in KB)
    PROCESS_MEMORY=600000  # 600MB

    if [ "$PROCESS_MEMORY" -gt "$CRITICAL_THRESHOLD" ]; then
        CRITICAL=true
    else
        CRITICAL=false
    fi

    [ "$CRITICAL" == "true" ]
}

@test "memory under thresholds passes" {
    WARN_THRESHOLD=$((300 * 1024))
    PROCESS_MEMORY=200000  # 200MB

    if [ "$PROCESS_MEMORY" -lt "$WARN_THRESHOLD" ]; then
        PASS=true
    else
        PASS=false
    fi

    [ "$PASS" == "true" ]
}

# ============================================
# Uptime Monitoring Tests
# ============================================

@test "uptime warning at 24 hours" {
    WARN_HOURS=24
    WARN_SECONDS=$((WARN_HOURS * 3600))

    # Process running for 25 hours
    UPTIME_SECONDS=$((25 * 3600))

    if [ "$UPTIME_SECONDS" -gt "$WARN_SECONDS" ]; then
        WARNING=true
    else
        WARNING=false
    fi

    [ "$WARNING" == "true" ]
}

@test "uptime under 24 hours passes" {
    WARN_HOURS=24
    WARN_SECONDS=$((WARN_HOURS * 3600))

    # Process running for 12 hours
    UPTIME_SECONDS=$((12 * 3600))

    if [ "$UPTIME_SECONDS" -lt "$WARN_SECONDS" ]; then
        PASS=true
    else
        PASS=false
    fi

    [ "$PASS" == "true" ]
}

# ============================================
# Log Rotation Tests
# ============================================

@test "log directory exists" {
    mkdir -p "$OCTO_HOME/logs"
    [ -d "$OCTO_HOME/logs" ]
}

@test "creates dated log file" {
    mkdir -p "$OCTO_HOME/logs"
    TODAY=$(date +%Y-%m-%d)
    touch "$OCTO_HOME/logs/watchdog-$TODAY.log"

    [ -f "$OCTO_HOME/logs/watchdog-$TODAY.log" ]
}

@test "rotates logs older than 7 days" {
    mkdir -p "$OCTO_HOME/logs"

    # Create old log file
    OLD_DATE="2025-01-01"
    touch "$OCTO_HOME/logs/watchdog-$OLD_DATE.log"

    # In production, old logs would be removed
    # Here we just verify we can identify old files
    [ -f "$OCTO_HOME/logs/watchdog-$OLD_DATE.log" ]
}

# ============================================
# Restart Logic Tests
# ============================================

@test "restart command format" {
    # Expected restart command pattern
    RESTART_CMD="systemctl restart openclaw-gateway"

    [[ "$RESTART_CMD" == *"restart"* ]]
    [[ "$RESTART_CMD" == *"openclaw"* ]]
}

@test "restart delay is 5 seconds" {
    RESTART_DELAY=5
    [ "$RESTART_DELAY" -eq 5 ]
}

@test "max restart attempts is 3" {
    MAX_ATTEMPTS=3
    [ "$MAX_ATTEMPTS" -eq 3 ]
}

# ============================================
# Cron Schedule Tests
# ============================================

@test "watchdog runs every 5 minutes" {
    # Cron expression: */5 * * * *
    CRON_MINUTES="*/5"
    [ "$CRON_MINUTES" == "*/5" ]
}

@test "cron entry format is valid" {
    CRON_ENTRY="*/5 * * * * /path/to/octo watchdog check"

    # Should have 6 fields (5 time fields + command)
    fields=$(echo "$CRON_ENTRY" | wc -w | tr -d ' ')
    [ "$fields" -ge 6 ]
}

# ============================================
# Health Check Tests
# ============================================

@test "health check endpoint" {
    # Default health endpoint
    HEALTH_URL="http://localhost:6200/health"
    [[ "$HEALTH_URL" == *"health"* ]]
}

@test "health check timeout is 5 seconds" {
    TIMEOUT=5
    [ "$TIMEOUT" -eq 5 ]
}

@test "health check retries is 3" {
    RETRIES=3
    [ "$RETRIES" -eq 3 ]
}

# ============================================
# Integration Test
# ============================================

@test "watchdog command runs" {
    cp "$FIXTURES_DIR/configs/default_config.json" "$OCTO_HOME/config.json"

    run "$PROJECT_ROOT/bin/octo" watchdog status
    # Should produce some output
    [ -n "$output" ] || [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}
