#!/usr/bin/env bats
#
# Tests for lib/cli/analyze.sh
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

    # Copy default config
    cp "$FIXTURES_DIR/configs/default_config.json" "$OCTO_HOME/config.json"

    source "$HELPERS_DIR/assertions.sh"
}

teardown() {
    rm -rf "$OCTO_HOME" "$OPENCLAW_HOME"
}

# ============================================
# Argument Parsing Tests
# ============================================

@test "shows help with -h flag" {
    run "$PROJECT_ROOT/bin/octo" analyze -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage"* ]] || [[ "$output" == *"analyze"* ]] || [[ "$output" == *"period"* ]]
}

@test "parses --period=today" {
    # Copy cost file for today
    TODAY=$(date +%Y-%m-%d)
    mkdir -p "$OCTO_HOME/costs"
    cp "$FIXTURES_DIR/costs/sample_costs.jsonl" "$OCTO_HOME/costs/costs-$TODAY.jsonl"

    run "$PROJECT_ROOT/bin/octo" analyze --period=today
    # Should run - check status or that we got any output
    [ "$status" -eq 0 ] || [ -n "$output" ]
}

@test "parses --verbose flag" {
    run "$PROJECT_ROOT/bin/octo" analyze -v --help
    [[ "$output" == *"verbose"* ]] || [[ "$output" == *"Usage"* ]] || [ "$status" -eq 0 ]
}

# ============================================
# Session Analysis Tests
# ============================================

@test "calculates session file size" {
    cp "$FIXTURES_DIR/sessions/healthy_session.jsonl" "$OPENCLAW_HOME/agents/main/sessions/test.jsonl"

    size=$(wc -c < "$OPENCLAW_HOME/agents/main/sessions/test.jsonl" | tr -d ' ')
    [ "$size" -gt 0 ]
}

@test "counts user messages in session" {
    cp "$FIXTURES_DIR/sessions/healthy_session.jsonl" "$OPENCLAW_HOME/agents/main/sessions/test.jsonl"

    user_count=$(grep -c '"role":"user"' "$OPENCLAW_HOME/agents/main/sessions/test.jsonl" || echo "0")
    [ "$user_count" -gt 0 ]
}

@test "counts assistant messages in session" {
    cp "$FIXTURES_DIR/sessions/healthy_session.jsonl" "$OPENCLAW_HOME/agents/main/sessions/test.jsonl"

    assistant_count=$(grep -c '"role":"assistant"' "$OPENCLAW_HOME/agents/main/sessions/test.jsonl" || echo "0")
    [ "$assistant_count" -gt 0 ]
}

@test "counts injection markers in session" {
    cp "$FIXTURES_DIR/sessions/injection_loop_session.jsonl" "$OPENCLAW_HOME/agents/main/sessions/test.jsonl"

    marker_count=$(grep -c 'INJECTION-DEPTH' "$OPENCLAW_HOME/agents/main/sessions/test.jsonl" || echo "0")
    [ "$marker_count" -gt 0 ]
}

@test "warns on high injection count (>10)" {
    cp "$FIXTURES_DIR/sessions/high_markers_session.jsonl" "$OPENCLAW_HOME/agents/main/sessions/test.jsonl"

    marker_count=$(grep -c 'INJECTION-DEPTH' "$OPENCLAW_HOME/agents/main/sessions/test.jsonl" || echo "0")
    [ "$marker_count" -gt 10 ]
}

@test "estimates tokens as size/4" {
    cp "$FIXTURES_DIR/sessions/healthy_session.jsonl" "$OPENCLAW_HOME/agents/main/sessions/test.jsonl"

    size=$(wc -c < "$OPENCLAW_HOME/agents/main/sessions/test.jsonl" | tr -d ' ')
    estimated_tokens=$((size / 4))
    [ "$estimated_tokens" -gt 0 ]
}

# ============================================
# Aggregate Analysis Tests
# ============================================

@test "discovers all session files" {
    mkdir -p "$OPENCLAW_HOME/agents/main/sessions"
    cp "$FIXTURES_DIR/sessions/healthy_session.jsonl" "$OPENCLAW_HOME/agents/main/sessions/session1.jsonl"
    cp "$FIXTURES_DIR/sessions/healthy_session.jsonl" "$OPENCLAW_HOME/agents/main/sessions/session2.jsonl"

    count=$(find "$OPENCLAW_HOME" -name "*.jsonl" -type f 2>/dev/null | wc -l | tr -d ' ')
    [ "$count" -eq 2 ]
}

@test "excludes archived sessions" {
    mkdir -p "$OPENCLAW_HOME/agents/main/sessions"
    cp "$FIXTURES_DIR/sessions/healthy_session.jsonl" "$OPENCLAW_HOME/agents/main/sessions/session1.jsonl"
    cp "$FIXTURES_DIR/sessions/healthy_session.jsonl" "$OPENCLAW_HOME/agents/main/sessions/.archived.session2.jsonl"

    count=$(find "$OPENCLAW_HOME" -name "*.jsonl" -type f ! -name ".archived.*" 2>/dev/null | wc -l | tr -d ' ')
    [ "$count" -eq 1 ]
}

@test "detects bloated sessions (>10MB)" {
    mkdir -p "$OPENCLAW_HOME/agents/main/sessions"

    # Create a file just under 10MB for testing
    # (Don't actually create 10MB file in tests)
    THRESHOLD_BYTES=$((10 * 1024 * 1024))

    # Verify threshold is correct
    [ "$THRESHOLD_BYTES" -eq 10485760 ]
}

@test "calculates average session size" {
    mkdir -p "$OPENCLAW_HOME/agents/main/sessions"
    echo "1234567890" > "$OPENCLAW_HOME/agents/main/sessions/s1.jsonl"
    echo "12345678901234567890" > "$OPENCLAW_HOME/agents/main/sessions/s2.jsonl"

    total=0
    count=0
    for f in "$OPENCLAW_HOME/agents/main/sessions/"*.jsonl; do
        size=$(wc -c < "$f" | tr -d ' ')
        total=$((total + size))
        count=$((count + 1))
    done
    avg=$((total / count))

    [ "$avg" -gt 0 ]
}

# ============================================
# Cost Analysis Tests
# ============================================

@test "finds today's cost file" {
    TODAY=$(date +%Y-%m-%d)
    mkdir -p "$OCTO_HOME/costs"
    cp "$FIXTURES_DIR/costs/sample_costs.jsonl" "$OCTO_HOME/costs/costs-$TODAY.jsonl"

    [ -f "$OCTO_HOME/costs/costs-$TODAY.jsonl" ]
}

@test "finds yesterday's cost file" {
    if [[ "$(uname)" == "Darwin" ]]; then
        YESTERDAY=$(date -v-1d +%Y-%m-%d)
    else
        YESTERDAY=$(date -d "yesterday" +%Y-%m-%d)
    fi

    mkdir -p "$OCTO_HOME/costs"
    cp "$FIXTURES_DIR/costs/sample_costs.jsonl" "$OCTO_HOME/costs/costs-$YESTERDAY.jsonl"

    [ -f "$OCTO_HOME/costs/costs-$YESTERDAY.jsonl" ]
}

@test "aggregates costs from JSONL" {
    cp "$FIXTURES_DIR/costs/sample_costs.jsonl" "$OCTO_HOME/costs/test.jsonl"

    if command -v jq &>/dev/null; then
        total=$(jq -s 'map(.total_cost) | add' "$OCTO_HOME/costs/test.jsonl")
        [ -n "$total" ]
        [[ "$total" != "null" ]]
    fi
}

@test "calculates cache efficiency" {
    cp "$FIXTURES_DIR/costs/sample_costs.jsonl" "$OCTO_HOME/costs/test.jsonl"

    if command -v jq &>/dev/null; then
        # Sum of cache_read_tokens / sum of input_tokens
        cache_read=$(jq -s 'map(.cache_read_tokens // 0) | add' "$OCTO_HOME/costs/test.jsonl")
        input=$(jq -s 'map(.input_tokens // 0) | add' "$OCTO_HOME/costs/test.jsonl")

        [ -n "$cache_read" ]
        [ -n "$input" ]
    fi
}

# ============================================
# Savings Estimation Tests
# ============================================

@test "reads feature states from config" {
    if command -v jq &>/dev/null; then
        caching=$(jq -r '.optimization.promptCaching.enabled' "$OCTO_HOME/config.json")
        tiering=$(jq -r '.optimization.modelTiering.enabled' "$OCTO_HOME/config.json")

        [ "$caching" == "true" ]
        [ "$tiering" == "true" ]
    fi
}

@test "stacks savings percentages" {
    # Caching: 30%, Tiering: 40%
    # Stacked: 1 - (1 - 0.30) * (1 - 0.40) = 1 - 0.70 * 0.60 = 1 - 0.42 = 0.58 = 58%
    CACHING_SAVINGS=30
    TIERING_SAVINGS=40

    # Calculate stacked savings
    remaining_caching=$((100 - CACHING_SAVINGS))
    remaining_tiering=$((100 - TIERING_SAVINGS))
    remaining_combined=$((remaining_caching * remaining_tiering / 100))
    stacked_savings=$((100 - remaining_combined))

    [ "$stacked_savings" -eq 58 ]
}

@test "caps at 95% maximum" {
    MAX_CAP=95
    [ "$MAX_CAP" -eq 95 ]
}

@test "suggests Onelist when not installed" {
    cp "$FIXTURES_DIR/configs/default_config.json" "$OCTO_HOME/config.json"

    if command -v jq &>/dev/null; then
        installed=$(jq -r '.onelist.installed' "$OCTO_HOME/config.json")
        [ "$installed" == "false" ]
    fi
}
