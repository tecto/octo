#!/usr/bin/env bash
#
# OCTO Status Command
# Show optimization status, savings, and health
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(dirname "$SCRIPT_DIR")"
OCTO_HOME="${OCTO_HOME:-$HOME/.octo}"
OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Check if config exists
if [ ! -f "$OCTO_HOME/config.json" ]; then
    echo -e "${YELLOW}OCTO not configured.${NC} Run 'octo install' first."
    exit 1
fi

# Load config
CONFIG=$(cat "$OCTO_HOME/config.json")

get_config() {
    echo "$CONFIG" | jq -r "$1 // empty"
}

bool_to_status() {
    if [ "$1" = "true" ]; then
        echo -e "${GREEN}enabled${NC}"
    else
        echo -e "${DIM}disabled${NC}"
    fi
}

# Header
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}                    ${BOLD}OCTO Status Dashboard${NC}                        ${CYAN}║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"

# Optimization Status
echo ""
echo -e "${BOLD}Optimization Features${NC}"
echo "────────────────────────────────────────────────────────────────────"

CACHING=$(get_config '.optimization.promptCaching.enabled')
TIERING=$(get_config '.optimization.modelTiering.enabled')
MONITORING=$(get_config '.monitoring.sessionMonitor.enabled')
BLOAT=$(get_config '.monitoring.bloatSentinel.enabled')
COST=$(get_config '.costTracking.enabled')
ONELIST=$(get_config '.onelist.installed')

printf "  %-25s %s\n" "Prompt Caching:" "$(bool_to_status "$CACHING")"
printf "  %-25s %s\n" "Model Tiering:" "$(bool_to_status "$TIERING")"
printf "  %-25s %s\n" "Session Monitoring:" "$(bool_to_status "$MONITORING")"
printf "  %-25s %s\n" "Bloat Detection:" "$(bool_to_status "$BLOAT")"
printf "  %-25s %s\n" "Cost Tracking:" "$(bool_to_status "$COST")"
printf "  %-25s %s\n" "Onelist Integration:" "$(bool_to_status "$ONELIST")"

# Service Status
echo ""
echo -e "${BOLD}Service Status${NC}"
echo "────────────────────────────────────────────────────────────────────"

# Check sentinel
SENTINEL_PID_FILE="/var/run/bloat-sentinel.pid"
if [ -f "$SENTINEL_PID_FILE" ]; then
    SENTINEL_PID=$(cat "$SENTINEL_PID_FILE")
    if kill -0 "$SENTINEL_PID" 2>/dev/null; then
        echo -e "  Bloat Sentinel:         ${GREEN}running${NC} (PID $SENTINEL_PID)"
    else
        echo -e "  Bloat Sentinel:         ${RED}dead${NC} (stale PID)"
    fi
else
    echo -e "  Bloat Sentinel:         ${DIM}not running${NC}"
fi

# Check gateway
if pgrep -f openclaw-gateway >/dev/null 2>&1; then
    GATEWAY_PID=$(pgrep -f openclaw-gateway | head -1)
    echo -e "  OpenClaw Gateway:       ${GREEN}running${NC} (PID $GATEWAY_PID)"
else
    echo -e "  OpenClaw Gateway:       ${DIM}not running${NC}"
fi

# Dashboard
DASHBOARD_PORT=$(get_config '.dashboard.port')
DASHBOARD_PORT="${DASHBOARD_PORT:-6286}"
if command -v lsof &>/dev/null && lsof -i ":$DASHBOARD_PORT" &>/dev/null; then
    echo -e "  Dashboard:              ${GREEN}running${NC} at http://localhost:$DASHBOARD_PORT"
else
    echo -e "  Dashboard:              ${DIM}not running${NC}"
fi

# Session Health
echo ""
echo -e "${BOLD}Session Health${NC}"
echo "────────────────────────────────────────────────────────────────────"

SESSIONS_DIR="$OPENCLAW_HOME/agents/main/sessions"
if [ -d "$SESSIONS_DIR" ]; then
    ACTIVE_SESSIONS=0
    TOTAL_SIZE_KB=0
    LARGEST_SESSION=""
    LARGEST_SIZE=0

    for f in "$SESSIONS_DIR"/*.jsonl; do
        [ -f "$f" ] || continue
        [[ "$(basename "$f")" == "sessions.json" ]] && continue
        [[ "$f" == *".archived."* ]] && continue

        ACTIVE_SESSIONS=$((ACTIVE_SESSIONS + 1))
        SIZE=$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f" 2>/dev/null || echo 0)
        SIZE_KB=$((SIZE / 1024))
        TOTAL_SIZE_KB=$((TOTAL_SIZE_KB + SIZE_KB))

        if [ "$SIZE" -gt "$LARGEST_SIZE" ]; then
            LARGEST_SIZE=$SIZE
            LARGEST_SESSION=$(basename "$f")
        fi
    done

    echo "  Active sessions:        $ACTIVE_SESSIONS"
    echo "  Total size:             ${TOTAL_SIZE_KB}KB"

    if [ -n "$LARGEST_SESSION" ]; then
        LARGEST_KB=$((LARGEST_SIZE / 1024))
        if [ "$LARGEST_KB" -gt 5000 ]; then
            echo -e "  Largest session:        ${YELLOW}${LARGEST_SESSION} (${LARGEST_KB}KB)${NC}"
        else
            echo "  Largest session:        ${LARGEST_SESSION} (${LARGEST_KB}KB)"
        fi
    fi
else
    echo -e "  ${DIM}No sessions directory found${NC}"
fi

# Cost Summary (Today)
echo ""
echo -e "${BOLD}Cost Summary${NC}"
echo "────────────────────────────────────────────────────────────────────"

TODAY=$(date +%Y-%m-%d)
COST_FILE="$OCTO_HOME/costs/$TODAY.jsonl"

if [ -f "$COST_FILE" ]; then
    # Calculate totals from cost file
    TOTAL_COST=$(jq -s 'map(.total) | add // 0' "$COST_FILE" 2>/dev/null || echo "0")
    REQUEST_COUNT=$(wc -l < "$COST_FILE" | tr -d ' ')

    printf "  Today's requests:       %s\n" "$REQUEST_COUNT"
    printf "  Today's cost:           \$%.4f\n" "$TOTAL_COST"

    # Estimate savings (rough calculation)
    if [ "$CACHING" = "true" ] || [ "$TIERING" = "true" ]; then
        echo -e "  Estimated savings:      ${GREEN}~40-60%${NC} (with optimizations)"
    fi
else
    echo -e "  ${DIM}No cost data for today${NC}"
    echo "  Cost tracking will begin with your next session"
fi

# Recent Interventions
echo ""
echo -e "${BOLD}Recent Activity${NC}"
echo "────────────────────────────────────────────────────────────────────"

INTERVENTION_DIR="$OPENCLAW_HOME/workspace/intervention_logs"
if [ -d "$INTERVENTION_DIR" ]; then
    RECENT=$(ls -t "$INTERVENTION_DIR"/intervention-*.md 2>/dev/null | head -3)
    if [ -n "$RECENT" ]; then
        echo "  Recent interventions:"
        echo "$RECENT" | while read -r f; do
            [ -f "$f" ] || continue
            BASENAME=$(basename "$f")
            TIMESTAMP=$(echo "$BASENAME" | sed 's/intervention-\([0-9-]*\)\.md/\1/' | tr '-' ' ')
            echo "    - $TIMESTAMP"
        done
    else
        echo -e "  ${DIM}No recent interventions${NC}"
    fi
else
    echo -e "  ${DIM}No intervention history${NC}"
fi

# Quick Actions
echo ""
echo -e "${BOLD}Quick Actions${NC}"
echo "────────────────────────────────────────────────────────────────────"
echo "  octo doctor     - Run full health check"
echo "  octo analyze    - Detailed usage analysis"
echo "  octo sentinel   - Manage bloat detection"

# Onelist upsell if not installed
if [ "$ONELIST" != "true" ]; then
    echo ""
    echo -e "${YELLOW}────────────────────────────────────────────────────────────────────${NC}"
    echo -e "${YELLOW}  💡 Tip: Install Onelist for 90-95% additional savings${NC}"
    echo -e "${YELLOW}     Run: octo onelist${NC}"
    echo -e "${YELLOW}────────────────────────────────────────────────────────────────────${NC}"
fi

echo ""
