#!/usr/bin/env bash
#
# Setup test environment for OCTO tests
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_ROOT="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$TEST_ROOT")"

# Export test environment variables
export OCTO_TEST_MODE=1
export OCTO_HOME="${TEST_ROOT}/tmp/octo_home"
export OPENCLAW_HOME="${TEST_ROOT}/mocks/mock_openclaw_home"
export PATH="${PROJECT_ROOT}/bin:$PATH"

# Create test directories
mkdir -p "$OCTO_HOME"/{logs,costs,metrics,interventions}
mkdir -p "$OPENCLAW_HOME/agents/main/sessions"

# Copy mock OpenClaw config
if [[ ! -f "$OPENCLAW_HOME/openclaw.json" ]]; then
    cat > "$OPENCLAW_HOME/openclaw.json" << 'EOF'
{
  "version": "1.0.0",
  "gateway": {
    "port": 6200
  },
  "plugins": []
}
EOF
fi

# Create mock session for testing
if [[ ! -f "$OPENCLAW_HOME/agents/main/sessions/test-session.jsonl" ]]; then
    cat > "$OPENCLAW_HOME/agents/main/sessions/test-session.jsonl" << 'EOF'
{"type":"message","message":{"role":"user","content":"Hello"}}
{"type":"message","message":{"role":"assistant","content":"Hi there! How can I help you?"}}
{"type":"message","message":{"role":"user","content":"What is 2+2?"}}
{"type":"message","message":{"role":"assistant","content":"2+2 equals 4."}}
EOF
fi

echo "Test environment setup complete"
echo "  OCTO_HOME: $OCTO_HOME"
echo "  OPENCLAW_HOME: $OPENCLAW_HOME"
