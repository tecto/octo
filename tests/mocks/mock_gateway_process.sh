#!/usr/bin/env bash
#
# Mock gateway process for OCTO testing
# Simulates openclaw-gateway
#

echo "Mock openclaw-gateway running on PID $$"
echo "Listening on port ${GATEWAY_PORT:-6200}"

# Create PID file if requested
if [[ -n "${GATEWAY_PID_FILE:-}" ]]; then
    echo $$ > "$GATEWAY_PID_FILE"
fi

# Allocate some memory to simulate real process
# shellcheck disable=SC2034
MEMORY_BUFFER=$(head -c 10M /dev/zero 2>/dev/null || dd if=/dev/zero bs=1M count=10 2>/dev/null)

# Keep running until killed
trap 'echo "Gateway shutting down"; exit 0' TERM INT

while true; do
    sleep 1
done
