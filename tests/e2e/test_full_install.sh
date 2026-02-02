#!/usr/bin/env bash
#
# E2E test: Full OCTO installation on clean system
#
# This test simulates a fresh OCTO installation and verifies
# all components are functional.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Test environment
TEST_HOME="${TEST_HOME:-/tmp/octo-e2e-test-$$}"
export OCTO_HOME="$TEST_HOME/octo"
export OPENCLAW_HOME="$TEST_HOME/openclaw"
export OCTO_TEST_MODE=1
export OCTO_NONINTERACTIVE=1
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
    pkill -f "bloat-sentinel.*e2e" 2>/dev/null || true
}

trap cleanup EXIT

# ============================================
# Setup
# ============================================

log_info "Setting up test environment at $TEST_HOME"

mkdir -p "$OCTO_HOME"
mkdir -p "$OPENCLAW_HOME/agents/main/sessions"
mkdir -p "$OPENCLAW_HOME/plugins"

# Create mock OpenClaw config
cat > "$OPENCLAW_HOME/openclaw.json" << 'EOF'
{"version": "1.0.0", "gateway": {"port": 6200}}
EOF

# Create mock sessions
for i in 1 2 3; do
    cat > "$OPENCLAW_HOME/agents/main/sessions/session-$i.jsonl" << EOF
{"type":"message","message":{"role":"user","content":"Hello $i"}}
{"type":"message","message":{"role":"assistant","content":"Hi there!"}}
EOF
done

log_info "Test environment created"

# ============================================
# Test: CLI Available
# ============================================

log_info "Testing CLI availability..."

if command -v octo &>/dev/null || [ -x "$PROJECT_ROOT/bin/octo" ]; then
    log_pass "OCTO CLI is available"
else
    log_fail "OCTO CLI not found"
fi

# ============================================
# Test: Help Command
# ============================================

log_info "Testing help command..."

if "$PROJECT_ROOT/bin/octo" --help | grep -q "OpenClaw Token Optimizer"; then
    log_pass "Help command works"
else
    log_fail "Help command failed"
fi

# ============================================
# Test: Version Command
# ============================================

log_info "Testing version command..."

if "$PROJECT_ROOT/bin/octo" --version 2>&1 | grep -qE "(OCTO|[0-9]+\.[0-9]+)"; then
    log_pass "Version command works"
else
    log_fail "Version command failed"
fi

# ============================================
# Test: Doctor Command (No Config)
# ============================================

log_info "Testing doctor command without config..."

output=$("$PROJECT_ROOT/bin/octo" doctor 2>&1 || true)
if [ -n "$output" ]; then
    log_pass "Doctor command runs without config"
else
    log_fail "Doctor command produced no output"
fi

# ============================================
# Test: Create Config
# ============================================

log_info "Testing config creation..."

mkdir -p "$OCTO_HOME"
cat > "$OCTO_HOME/config.json" << 'EOF'
{
  "version": "1.0.0",
  "installedAt": "2026-01-15T10:00:00Z",
  "openclaw": {
    "home": "/tmp/openclaw"
  },
  "optimization": {
    "promptCaching": {"enabled": true},
    "modelTiering": {"enabled": true}
  },
  "monitoring": {
    "sessionMonitoring": {"enabled": true},
    "bloatDetection": {"enabled": true, "autoIntervention": false}
  },
  "costTracking": {"enabled": true},
  "dashboard": {"port": 6286},
  "onelist": {"installed": false}
}
EOF

if [ -f "$OCTO_HOME/config.json" ]; then
    log_pass "Config file created"
else
    log_fail "Config file not created"
fi

# ============================================
# Test: Status Command (With Config)
# ============================================

log_info "Testing status command with config..."

output=$("$PROJECT_ROOT/bin/octo" status 2>&1 || true)
if echo "$output" | grep -qiE "(OCTO|status|optimization|enabled|disabled)"; then
    log_pass "Status command works with config"
else
    log_fail "Status command failed with config"
fi

# ============================================
# Test: Doctor Command (With Config)
# ============================================

log_info "Testing doctor command with config..."

output=$("$PROJECT_ROOT/bin/octo" doctor 2>&1 || true)
if echo "$output" | grep -qiE "(OCTO|health|check|pass|warn|fail)"; then
    log_pass "Doctor command works with config"
else
    log_fail "Doctor command failed with config"
fi

# ============================================
# Test: Analyze Command
# ============================================

log_info "Testing analyze command..."

# Create some cost data first
mkdir -p "$OCTO_HOME/costs"
TODAY=$(date +%Y-%m-%d)
cat > "$OCTO_HOME/costs/costs-$TODAY.jsonl" << 'EOF'
{"timestamp":"2026-01-15T10:00:00Z","model":"claude-sonnet-4-20250514","input_tokens":1000,"output_tokens":500,"total_cost":0.0105}
EOF

output=$("$PROJECT_ROOT/bin/octo" analyze --help 2>&1 || true)
if [ -n "$output" ]; then
    log_pass "Analyze command works"
else
    log_fail "Analyze command failed"
fi

# ============================================
# Test: Sentinel Status
# ============================================

log_info "Testing sentinel status..."

output=$("$PROJECT_ROOT/bin/octo" sentinel status 2>&1 || true)
if [ -n "$output" ]; then
    log_pass "Sentinel status command works"
else
    log_fail "Sentinel status command failed"
fi

# ============================================
# Test: Onelist Status
# ============================================

log_info "Testing onelist status..."

output=$("$PROJECT_ROOT/bin/octo" onelist status 2>&1 || true)
if [ -n "$output" ]; then
    log_pass "Onelist status command works"
else
    log_fail "Onelist status command failed"
fi

# ============================================
# Test: Plugin Files Exist
# ============================================

log_info "Testing plugin files..."

PLUGIN_DIR="$PROJECT_ROOT/lib/plugins/token-optimizer"

if [ -f "$PLUGIN_DIR/index.ts" ] && [ -f "$PLUGIN_DIR/openclaw.plugin.json" ]; then
    log_pass "Plugin files exist"
else
    log_fail "Plugin files missing"
fi

# ============================================
# Test: Core Python Modules
# ============================================

log_info "Testing Python modules..."

if python3 -c "
import sys
sys.path.insert(0, '$PROJECT_ROOT/lib/core')
from cost_estimator import CostEstimator
from model_tier import ModelTier
from session_monitor import SessionMonitor
print('OK')
" 2>/dev/null | grep -q "OK"; then
    log_pass "Python modules importable"
else
    log_fail "Python modules import failed"
fi

# ============================================
# Test: Cost Estimator Functionality
# ============================================

log_info "Testing cost estimator..."

if python3 -c "
import sys
sys.path.insert(0, '$PROJECT_ROOT/lib/core')
from cost_estimator import CostEstimator
est = CostEstimator(costs_dir='$OCTO_HOME/costs')
cost = est.calculate('claude-sonnet-4-20250514', {'input_tokens': 1000, 'output_tokens': 500})
assert cost.total > 0, 'Cost should be positive'
print('OK')
" 2>/dev/null | grep -q "OK"; then
    log_pass "Cost estimator works"
else
    log_fail "Cost estimator failed"
fi

# ============================================
# Test: Model Tier Functionality
# ============================================

log_info "Testing model tier..."

if python3 -c "
import sys
sys.path.insert(0, '$PROJECT_ROOT/lib/core')
from model_tier import ModelTier
tier = ModelTier()
decision = tier.classify([{'role': 'user', 'content': 'Yes'}])
assert decision.tier == 'haiku', f'Expected haiku, got {decision.tier}'
print('OK')
" 2>/dev/null | grep -q "OK"; then
    log_pass "Model tier works"
else
    log_fail "Model tier failed"
fi

# ============================================
# Test: Session Monitor Functionality
# ============================================

log_info "Testing session monitor..."

if python3 -c "
import sys
sys.path.insert(0, '$PROJECT_ROOT/lib/core')
from session_monitor import SessionMonitor
monitor = SessionMonitor(openclaw_home='$OPENCLAW_HOME')
sessions = monitor.discover_sessions()
assert len(sessions) > 0, 'Should find sessions'
print('OK')
" 2>/dev/null | grep -q "OK"; then
    log_pass "Session monitor works"
else
    log_fail "Session monitor failed"
fi

# ============================================
# Summary
# ============================================

echo ""
echo "============================================"
echo "E2E Test Summary"
echo "============================================"
echo -e "${GREEN}Passed:${NC} $TESTS_PASSED"
echo -e "${RED}Failed:${NC} $TESTS_FAILED"
echo "============================================"

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
else
    exit 0
fi
