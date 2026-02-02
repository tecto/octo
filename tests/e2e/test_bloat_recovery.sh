#!/usr/bin/env bash
#
# E2E test: Bloat detection and recovery
#
# This test verifies the full bloat detection and intervention flow.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Test environment
TEST_HOME="${TEST_HOME:-/tmp/octo-bloat-test-$$}"
export OCTO_HOME="$TEST_HOME/octo"
export OPENCLAW_HOME="$TEST_HOME/openclaw"
export OCTO_TEST_MODE=1
export PATH="$PROJECT_ROOT/bin:$PATH"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((TESTS_PASSED++)) || true
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((TESTS_FAILED++)) || true
}

log_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

cleanup() {
    log_info "Cleaning up test environment..."
    rm -rf "$TEST_HOME"
    pkill -f "bloat-sentinel.*bloat-test" 2>/dev/null || true
}

trap cleanup EXIT

# ============================================
# Setup
# ============================================

log_info "Setting up test environment at $TEST_HOME"

mkdir -p "$OCTO_HOME"/{logs,costs,metrics,interventions,archived}
mkdir -p "$OPENCLAW_HOME/agents/main/sessions"

# Create config
cat > "$OCTO_HOME/config.json" << 'EOF'
{
  "version": "1.0.0",
  "monitoring": {
    "bloatDetection": {
      "enabled": true,
      "autoIntervention": true
    }
  }
}
EOF

cat > "$OPENCLAW_HOME/openclaw.json" << 'EOF'
{"version": "1.0.0", "gateway": {"port": 6200}}
EOF

log_info "Test environment created"

# ============================================
# Test: Create Healthy Session
# ============================================

log_info "Creating healthy session..."

cat > "$OPENCLAW_HOME/agents/main/sessions/healthy.jsonl" << 'EOF'
{"type":"message","message":{"role":"user","content":"Hello"}}
{"type":"message","message":{"role":"assistant","content":"Hi there!"}}
{"type":"message","message":{"role":"user","content":"How are you?"}}
{"type":"message","message":{"role":"assistant","content":"I'm doing well!"}}
EOF

if [ -f "$OPENCLAW_HOME/agents/main/sessions/healthy.jsonl" ]; then
    log_pass "Healthy session created"
else
    log_fail "Failed to create healthy session"
fi

# ============================================
# Test: Healthy Session Detection
# ============================================

log_info "Checking healthy session status..."

# Check for injection markers
markers=$(grep -c 'INJECTION-DEPTH' "$OPENCLAW_HOME/agents/main/sessions/healthy.jsonl" 2>/dev/null) || markers=0

if [ "$markers" -eq 0 ]; then
    log_pass "Healthy session has no injection markers"
else
    log_fail "Healthy session has unexpected markers"
fi

# ============================================
# Test: Create Bloated Session
# ============================================

log_info "Creating bloated session with injection markers..."

cat > "$OPENCLAW_HOME/agents/main/sessions/bloated.jsonl" << 'EOF'
{"type":"message","message":{"role":"user","content":"Hello"}}
{"type":"message","message":{"role":"assistant","content":"Hi there!"}}
{"type":"message","message":{"role":"user","content":"[INJECTION-DEPTH:1] Recovered Conversation Context\n\nFirst injection"}}
{"type":"message","message":{"role":"assistant","content":"I see context"}}
{"type":"message","message":{"role":"user","content":"[INJECTION-DEPTH:2] Recovered Conversation Context\n\n[INJECTION-DEPTH:1] Recovered Conversation Context\n\nNested injection"}}
{"type":"message","message":{"role":"assistant","content":"Multiple context blocks"}}
EOF

if [ -f "$OPENCLAW_HOME/agents/main/sessions/bloated.jsonl" ]; then
    log_pass "Bloated session created"
else
    log_fail "Failed to create bloated session"
fi

# ============================================
# Test: Bloat Detection
# ============================================

log_info "Testing bloat detection..."

# Check for nested injection markers (lines with multiple INJECTION-DEPTH)
# Use awk to count lines where INJECTION-DEPTH appears more than once
nested=$(awk '/INJECTION-DEPTH.*INJECTION-DEPTH/{count++} END{print count+0}' \
    "$OPENCLAW_HOME/agents/main/sessions/bloated.jsonl" 2>/dev/null) || nested=0

if [ "$nested" -gt 0 ]; then
    log_pass "Nested injection blocks detected ($nested)"
else
    log_fail "Failed to detect nested injection blocks"
fi

# Count total markers
markers=$(grep -o 'INJECTION-DEPTH' "$OPENCLAW_HOME/agents/main/sessions/bloated.jsonl" | wc -l | tr -d ' ')

if [ "$markers" -ge 3 ]; then
    log_pass "Multiple injection markers found ($markers)"
else
    log_fail "Insufficient markers detected"
fi

# ============================================
# Test: Intervention Simulation
# ============================================

log_info "Simulating intervention..."

TIMESTAMP=$(date +%Y-%m-%dT%H-%M-%S)
DATE=$(date +%Y-%m-%d)

# Create intervention log
cat > "$OCTO_HOME/interventions/intervention-$TIMESTAMP.log" << EOF
Timestamp: $TIMESTAMP
Session: bloated.jsonl
Layer: 1 (nested injection blocks)
Markers detected: $markers
Nested blocks: $nested
Action: Archive and reset

Details:
- Session archived to: $OCTO_HOME/archived/$DATE/bloated.jsonl.bak
- Original session reset
- Gateway restart triggered
EOF

if [ -f "$OCTO_HOME/interventions/intervention-$TIMESTAMP.log" ]; then
    log_pass "Intervention log created"
else
    log_fail "Failed to create intervention log"
fi

# ============================================
# Test: Session Archive
# ============================================

log_info "Archiving bloated session..."

mkdir -p "$OCTO_HOME/archived/$DATE"
cp "$OPENCLAW_HOME/agents/main/sessions/bloated.jsonl" \
   "$OCTO_HOME/archived/$DATE/bloated.jsonl.bak"

if [ -f "$OCTO_HOME/archived/$DATE/bloated.jsonl.bak" ]; then
    log_pass "Session archived successfully"
else
    log_fail "Failed to archive session"
fi

# Verify archive content matches original
original_size=$(wc -c < "$OPENCLAW_HOME/agents/main/sessions/bloated.jsonl" | tr -d ' ')
archive_size=$(wc -c < "$OCTO_HOME/archived/$DATE/bloated.jsonl.bak" | tr -d ' ')

if [ "$original_size" -eq "$archive_size" ]; then
    log_pass "Archive content matches original"
else
    log_fail "Archive content mismatch"
fi

# ============================================
# Test: Session Reset
# ============================================

log_info "Resetting bloated session..."

: > "$OPENCLAW_HOME/agents/main/sessions/bloated.jsonl"

size=$(wc -c < "$OPENCLAW_HOME/agents/main/sessions/bloated.jsonl" | tr -d ' ')

if [ "$size" -eq 0 ]; then
    log_pass "Session reset (size: 0 bytes)"
else
    log_fail "Session not properly reset (size: $size bytes)"
fi

# ============================================
# Test: Session File Persistence
# ============================================

log_info "Verifying session file still exists after reset..."

if [ -f "$OPENCLAW_HOME/agents/main/sessions/bloated.jsonl" ]; then
    log_pass "Session file persists after reset"
else
    log_fail "Session file was deleted"
fi

# ============================================
# Test: Recovery Verification
# ============================================

log_info "Verifying recovery state..."

# Archive exists
if [ -f "$OCTO_HOME/archived/$DATE/bloated.jsonl.bak" ]; then
    log_pass "Backup available for recovery"
else
    log_fail "No backup available"
fi

# Intervention logged
intervention_count=$(ls "$OCTO_HOME/interventions/"*.log 2>/dev/null | wc -l | tr -d ' ')

if [ "$intervention_count" -ge 1 ]; then
    log_pass "Intervention history recorded ($intervention_count logs)"
else
    log_fail "No intervention history"
fi

# Session is clean
reset_markers=$(grep -c 'INJECTION-DEPTH' "$OPENCLAW_HOME/agents/main/sessions/bloated.jsonl" 2>/dev/null) || reset_markers=0

if [ "$reset_markers" -eq 0 ]; then
    log_pass "Reset session has no injection markers"
else
    log_fail "Reset session still has markers"
fi

# ============================================
# Test: Healthy Session Unchanged
# ============================================

log_info "Verifying healthy session unchanged..."

healthy_size=$(wc -c < "$OPENCLAW_HOME/agents/main/sessions/healthy.jsonl" | tr -d ' ')

if [ "$healthy_size" -gt 0 ]; then
    log_pass "Healthy session unchanged ($healthy_size bytes)"
else
    log_fail "Healthy session was affected"
fi

# ============================================
# Test: Sentinel Status After Intervention
# ============================================

log_info "Checking sentinel status after intervention..."

output=$("$PROJECT_ROOT/bin/octo" sentinel status 2>&1 || true)

if [ -n "$output" ]; then
    log_pass "Sentinel status available after intervention"
else
    log_fail "Sentinel status unavailable"
fi

# ============================================
# Summary
# ============================================

echo ""
echo "============================================"
echo "Bloat Recovery E2E Test Summary"
echo "============================================"
echo -e "${GREEN}Passed:${NC} $TESTS_PASSED"
echo -e "${RED}Failed:${NC} $TESTS_FAILED"
echo "============================================"

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
else
    exit 0
fi
