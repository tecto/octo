#!/usr/bin/env bash
#
# Teardown test environment for OCTO tests
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_ROOT="$(dirname "$SCRIPT_DIR")"

# Remove test temporary files
rm -rf "${TEST_ROOT}/tmp"

# Kill any lingering test processes
pkill -f "mock_gateway_process" 2>/dev/null || true
pkill -f "bloat-sentinel.*test" 2>/dev/null || true

echo "Test environment cleaned up"
