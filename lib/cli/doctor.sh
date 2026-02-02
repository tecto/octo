#!/usr/bin/env bash
#
# OCTO Doctor Command
# Health check and diagnostics
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

# Counters
CHECKS_PASSED=0
CHECKS_WARNED=0
CHECKS_FAILED=0

check_pass() {
    echo -e "  ${GREEN}✓${NC} $1"
    CHECKS_PASSED=$((CHECKS_PASSED + 1))
}

check_warn() {
    echo -e "  ${YELLOW}⚠${NC} $1"
    CHECKS_WARNED=$((CHECKS_WARNED + 1))
}

check_fail() {
    echo -e "  ${RED}✗${NC} $1"
    CHECKS_FAILED=$((CHECKS_FAILED + 1))
}

check_info() {
    echo -e "  ${BLUE}•${NC} $1"
}

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}                    ${BOLD}OCTO Health Check${NC}                            ${CYAN}║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"

# 1. Configuration Check
echo ""
echo -e "${BOLD}Configuration${NC}"
echo "────────────────────────────────────────────────────────────────────"

if [ -f "$OCTO_HOME/config.json" ]; then
    check_pass "OCTO configuration found"

    # Validate JSON
    if jq . "$OCTO_HOME/config.json" >/dev/null 2>&1; then
        check_pass "Configuration is valid JSON"
    else
        check_fail "Configuration has invalid JSON"
    fi
else
    check_fail "OCTO not configured - run 'octo install'"
fi

if [ -d "$OPENCLAW_HOME" ]; then
    check_pass "OpenClaw directory found"
else
    check_fail "OpenClaw directory not found at $OPENCLAW_HOME"
fi

if [ -f "$OPENCLAW_HOME/openclaw.json" ]; then
    check_pass "OpenClaw configuration found"
else
    check_warn "OpenClaw configuration not found"
fi

# 2. Dependencies Check
echo ""
echo -e "${BOLD}Dependencies${NC}"
echo "────────────────────────────────────────────────────────────────────"

if command -v python3 &>/dev/null; then
    PY_VERSION=$(python3 --version 2>&1 | cut -d' ' -f2)
    check_pass "Python 3 found ($PY_VERSION)"
else
    check_fail "Python 3 not found"
fi

if command -v jq &>/dev/null; then
    check_pass "jq found"
else
    check_warn "jq not found - some features may not work"
fi

if command -v curl &>/dev/null; then
    check_pass "curl found"
else
    check_warn "curl not found"
fi

# 3. Gateway Check
echo ""
echo -e "${BOLD}OpenClaw Gateway${NC}"
echo "────────────────────────────────────────────────────────────────────"

GATEWAY_PIDS=$(pgrep -f openclaw-gateway 2>/dev/null || true)

if [ -n "$GATEWAY_PIDS" ]; then
    GATEWAY_PID=$(echo "$GATEWAY_PIDS" | head -1)
    check_pass "Gateway is running (PID $GATEWAY_PID)"

    # Check memory usage
    if [ -f "/proc/$GATEWAY_PID/status" ]; then
        RSS_KB=$(grep VmRSS /proc/$GATEWAY_PID/status 2>/dev/null | awk '{print $2}' || echo 0)
        RSS_MB=$((RSS_KB / 1024))

        if [ "$RSS_MB" -gt 500 ]; then
            check_warn "Gateway memory usage high: ${RSS_MB}MB"
        elif [ "$RSS_MB" -gt 300 ]; then
            check_info "Gateway memory: ${RSS_MB}MB (elevated)"
        else
            check_pass "Gateway memory: ${RSS_MB}MB"
        fi
    fi

    # Check uptime
    if [ -d "/proc/$GATEWAY_PID" ]; then
        START_TIME=$(stat -c %Y /proc/$GATEWAY_PID 2>/dev/null || echo 0)
        NOW=$(date +%s)
        AGE_HOURS=$(( (NOW - START_TIME) / 3600 ))

        if [ "$AGE_HOURS" -gt 24 ]; then
            check_warn "Gateway uptime: ${AGE_HOURS}h (consider restart)"
        else
            check_pass "Gateway uptime: ${AGE_HOURS}h"
        fi
    fi
else
    check_info "Gateway not running"
fi

# 4. Session Health
echo ""
echo -e "${BOLD}Session Health${NC}"
echo "────────────────────────────────────────────────────────────────────"

SESSIONS_DIR="$OPENCLAW_HOME/agents/main/sessions"
if [ -d "$SESSIONS_DIR" ]; then
    BLOATED_SESSIONS=0
    HIGH_MARKER_SESSIONS=0

    for f in "$SESSIONS_DIR"/*.jsonl; do
        [ -f "$f" ] || continue
        [[ "$(basename "$f")" == "sessions.json" ]] && continue
        [[ "$f" == *".archived."* ]] && continue

        SIZE=$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f" 2>/dev/null || echo 0)
        SIZE_KB=$((SIZE / 1024))

        # Check for bloated sessions
        if [ "$SIZE_KB" -gt 10240 ]; then
            BLOATED_SESSIONS=$((BLOATED_SESSIONS + 1))
        fi

        # Check for injection markers
        MARKERS=$(grep -c "INJECTION-DEPTH" "$f" 2>/dev/null || echo 0)
        if [ "$MARKERS" -gt 10 ]; then
            HIGH_MARKER_SESSIONS=$((HIGH_MARKER_SESSIONS + 1))
        fi
    done

    if [ "$BLOATED_SESSIONS" -gt 0 ]; then
        check_fail "$BLOATED_SESSIONS sessions exceed 10MB"
    else
        check_pass "No bloated sessions detected"
    fi

    if [ "$HIGH_MARKER_SESSIONS" -gt 0 ]; then
        check_warn "$HIGH_MARKER_SESSIONS sessions have high injection counts"
    else
        check_pass "Injection counts normal"
    fi
else
    check_info "Sessions directory not found"
fi

# 5. Sentinel Check
echo ""
echo -e "${BOLD}Bloat Sentinel${NC}"
echo "────────────────────────────────────────────────────────────────────"

SENTINEL_PID_FILE="/var/run/bloat-sentinel.pid"
if [ -f "$SENTINEL_PID_FILE" ]; then
    SENTINEL_PID=$(cat "$SENTINEL_PID_FILE")
    if kill -0 "$SENTINEL_PID" 2>/dev/null; then
        check_pass "Sentinel running (PID $SENTINEL_PID)"
    else
        check_warn "Sentinel PID stale - restart recommended"
    fi
else
    if jq -e '.monitoring.bloatSentinel.enabled == true' "$OCTO_HOME/config.json" >/dev/null 2>&1; then
        check_warn "Sentinel enabled but not running"
        check_info "Start with: octo sentinel daemon"
    else
        check_info "Sentinel disabled in configuration"
    fi
fi

# 6. Log Check
echo ""
echo -e "${BOLD}Recent Errors${NC}"
echo "────────────────────────────────────────────────────────────────────"

TODAY=$(date +%Y-%m-%d)
LOG_FILE="/tmp/openclaw/openclaw-$TODAY.log"

if [ -f "$LOG_FILE" ]; then
    # Check for rate limit errors
    RATE_ERRORS=$(grep -c "rate_limit\|cooldown" "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "$RATE_ERRORS" -gt 10 ]; then
        check_warn "High rate limit errors today: $RATE_ERRORS"
    elif [ "$RATE_ERRORS" -gt 0 ]; then
        check_info "Rate limit errors today: $RATE_ERRORS"
    else
        check_pass "No rate limit errors today"
    fi

    # Check for overflow errors
    OVERFLOW=$(grep -c "overflow\|too large" "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "$OVERFLOW" -gt 0 ]; then
        check_fail "Context overflow errors: $OVERFLOW"
    else
        check_pass "No context overflow errors"
    fi
else
    check_info "No log file for today"
fi

# 7. Disk Space
echo ""
echo -e "${BOLD}Disk Space${NC}"
echo "────────────────────────────────────────────────────────────────────"

DISK_PCT=$(df "$HOME" 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%' || echo "0")
DISK_AVAIL=$(df -h "$HOME" 2>/dev/null | tail -1 | awk '{print $4}' || echo "unknown")

if [ "$DISK_PCT" -gt 90 ]; then
    check_fail "Disk usage critical: ${DISK_PCT}% (${DISK_AVAIL} available)"
elif [ "$DISK_PCT" -gt 80 ]; then
    check_warn "Disk usage elevated: ${DISK_PCT}% (${DISK_AVAIL} available)"
else
    check_pass "Disk usage: ${DISK_PCT}% (${DISK_AVAIL} available)"
fi

# 8. Onelist Check (if installed)
if [ -f "$OCTO_HOME/config.json" ]; then
    ONELIST_INSTALLED=$(jq -r '.onelist.installed // false' "$OCTO_HOME/config.json")
    if [ "$ONELIST_INSTALLED" = "true" ]; then
        echo ""
        echo -e "${BOLD}Onelist Integration${NC}"
        echo "────────────────────────────────────────────────────────────────────"

        # Check PostgreSQL
        if command -v pg_isready &>/dev/null && pg_isready -q 2>/dev/null; then
            check_pass "PostgreSQL is running"
        else
            check_warn "PostgreSQL not responding"
        fi

        # Check Onelist service
        if pgrep -f "beam.smp" >/dev/null 2>&1; then
            check_pass "Onelist service running"
        else
            check_warn "Onelist service not detected"
        fi
    fi
fi

# Summary
echo ""
echo "════════════════════════════════════════════════════════════════════"

TOTAL=$((CHECKS_PASSED + CHECKS_WARNED + CHECKS_FAILED))

if [ "$CHECKS_FAILED" -eq 0 ] && [ "$CHECKS_WARNED" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}  ✓ All $TOTAL checks passed - system healthy${NC}"
elif [ "$CHECKS_FAILED" -eq 0 ]; then
    echo -e "${YELLOW}${BOLD}  ⚠ $CHECKS_PASSED passed, $CHECKS_WARNED warnings${NC}"
else
    echo -e "${RED}${BOLD}  ✗ $CHECKS_PASSED passed, $CHECKS_WARNED warnings, $CHECKS_FAILED failed${NC}"
fi

echo "════════════════════════════════════════════════════════════════════"

# Recommendations
if [ "$CHECKS_FAILED" -gt 0 ] || [ "$CHECKS_WARNED" -gt 0 ]; then
    echo ""
    echo -e "${BOLD}Recommendations:${NC}"

    if [ "$CHECKS_FAILED" -gt 0 ]; then
        echo "  • Address failed checks before continuing"
        echo "  • Run 'octo surgery' if session issues detected"
    fi

    if [ "$CHECKS_WARNED" -gt 0 ]; then
        echo "  • Review warnings and take action if needed"
        echo "  • Run 'octo analyze' for detailed insights"
    fi
fi

echo ""

# Exit with appropriate code
if [ "$CHECKS_FAILED" -gt 0 ]; then
    exit 2
elif [ "$CHECKS_WARNED" -gt 0 ]; then
    exit 1
else
    exit 0
fi
