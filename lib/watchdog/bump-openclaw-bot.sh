#!/usr/bin/env bash
#
# OCTO Surgery - OpenClaw Recovery Script v3.0
#
# SAFE BY DEFAULT: Only performs health checks unless problems are found
# and user explicitly confirms the action.
#
# Usage: octo surgery [OPTIONS]
#   -c, --check-only     Health check only, never bump (default)
#   -y, --yes            Auto-confirm bump if problems found
#   --self               Self-bump mode: save diagnostics, notify on wake
#   -a, --agent NAME     Agent name (default: main)
#   -h, --help           Show this help
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OCTO_HOME="${OCTO_HOME:-$HOME/.octo}"
OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"

# Configuration
AGENT_NAME="main"
CHECK_ONLY=true
AUTO_CONFIRM=false
SELF_BUMP=false

# Thresholds
MAX_MEMORY_MB=500
MAX_SESSION_MB=10
MAX_INJECTION_MARKERS=50
RATE_LIMIT_COOLDOWN=10

# Warning thresholds
WARN_MEMORY_MB=300
WARN_SESSION_MB=2
WARN_INJECTION_MARKERS=10

# Paths
BUMP_LOG_DIR="$OPENCLAW_HOME/workspace/bump_log"
WATCHDOG_NOTIFY="$OPENCLAW_HOME/workspace/.surgery-bump-notice"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Results
CRITICAL_PROBLEMS=()
WARNINGS=()
GATEWAY_RUNNING=false
GATEWAY_PID=""
DIAGNOSTICS=""

show_help() {
    echo "OCTO Surgery - OpenClaw Recovery Script"
    echo ""
    echo "Usage: octo surgery [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -c, --check-only     Health check only, never bump (default)"
    echo "  -y, --yes            Auto-confirm bump if problems found"
    echo "  --self               Self-bump mode with diagnostics"
    echo "  -a, --agent NAME     Agent name (default: main)"
    echo "  -h, --help           Show this help"
    echo ""
    echo "Examples:"
    echo "  octo surgery                    # Health check (safe, no changes)"
    echo "  octo surgery -y                 # Auto-fix if problems found"
    echo "  octo surgery --self             # Self-bump with diagnostics"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -a|--agent) AGENT_NAME="$2"; shift 2 ;;
        -c|--check-only) CHECK_ONLY=true; shift ;;
        -y|--yes) AUTO_CONFIRM=true; CHECK_ONLY=false; shift ;;
        --self) SELF_BUMP=true; AUTO_CONFIRM=true; CHECK_ONLY=false; shift ;;
        -h|--help) show_help ;;
        *) echo "Unknown option: $1"; show_help ;;
    esac
done

# Derived paths
AGENT_DIR="$OPENCLAW_HOME/agents/$AGENT_NAME"
SESSIONS_DIR="$AGENT_DIR/sessions"
MAX_SESSION_BYTES=$((MAX_SESSION_MB * 1024 * 1024))

log_header() { echo -e "\n${BOLD}$1${NC}"; echo "$(echo "$1" | sed 's/./-/g')"; }
log_info() { echo -e "  ${BLUE}•${NC} $1"; }
log_ok() { echo -e "  ${GREEN}✓${NC} $1"; }
log_warn() { echo -e "  ${YELLOW}⚠${NC} $1"; WARNINGS+=("$1"); }
log_critical() { echo -e "  ${RED}✗${NC} $1"; CRITICAL_PROBLEMS+=("$1"); }

add_diagnostic() {
    DIAGNOSTICS="${DIAGNOSTICS}$1\n"
}

check_prerequisites() {
    if [ ! -d "$OPENCLAW_HOME" ]; then
        echo "Error: OpenClaw directory not found: $OPENCLAW_HOME"
        exit 1
    fi

    if [ ! -d "$AGENT_DIR" ]; then
        echo "Error: Agent '$AGENT_NAME' not found"
        exit 1
    fi
}

check_gateway() {
    log_header "Gateway Status"
    add_diagnostic "=== GATEWAY STATUS ==="

    GATEWAY_PIDS=$(pgrep -f openclaw-gateway 2>/dev/null | tr '\n' ' ' || true)

    if [ -z "$GATEWAY_PIDS" ]; then
        log_critical "Gateway is NOT running"
        add_diagnostic "Gateway: NOT RUNNING"
        GATEWAY_RUNNING=false
        return
    fi

    GATEWAY_RUNNING=true
    GATEWAY_PID=$(echo "$GATEWAY_PIDS" | awk '{print $1}')
    PROC_COUNT=$(echo "$GATEWAY_PIDS" | wc -w | tr -d ' ')
    log_ok "Running ($PROC_COUNT processes)"
    add_diagnostic "Gateway: Running (PIDs: $GATEWAY_PIDS)"

    # Memory check (Linux only)
    if [ -f "/proc/$GATEWAY_PID/status" ]; then
        RSS_KB=$(grep VmRSS /proc/$GATEWAY_PID/status 2>/dev/null | awk '{print $2}' || echo 0)
        RSS_MB=$((RSS_KB / 1024))
        add_diagnostic "Memory: ${RSS_MB}MB"

        if [ "$RSS_MB" -gt "$MAX_MEMORY_MB" ] 2>/dev/null; then
            log_critical "Memory: ${RSS_MB}MB (exceeds ${MAX_MEMORY_MB}MB)"
        elif [ "$RSS_MB" -gt "$WARN_MEMORY_MB" ] 2>/dev/null; then
            log_warn "Memory: ${RSS_MB}MB (elevated)"
        else
            log_ok "Memory: ${RSS_MB}MB"
        fi
    fi
}

check_sessions() {
    log_header "Sessions"
    add_diagnostic "=== SESSIONS ==="

    if [ ! -d "$SESSIONS_DIR" ]; then
        log_warn "Sessions directory not found"
        return
    fi

    TOTAL_SESSIONS=0
    TOTAL_SIZE_KB=0
    BLOATED_SESSIONS=()

    for f in "$SESSIONS_DIR"/*.jsonl; do
        [ -f "$f" ] || continue
        [[ "$(basename "$f")" == "sessions.json" ]] && continue
        [[ "$f" == *".archived."* ]] && continue

        TOTAL_SESSIONS=$((TOTAL_SESSIONS + 1))
        FILENAME=$(basename "$f")
        SESSION_ID="${FILENAME%.jsonl}"

        if [[ "$OSTYPE" == "darwin"* ]]; then
            SIZE=$(stat -f%z "$f" 2>/dev/null || echo 0)
        else
            SIZE=$(stat -c%s "$f" 2>/dev/null || echo 0)
        fi

        SIZE_KB=$((SIZE / 1024))
        SIZE_MB=$((SIZE / 1024 / 1024))
        TOTAL_SIZE_KB=$((TOTAL_SIZE_KB + SIZE_KB))

        MARKERS=$(grep -c "INJECTION-DEPTH" "$f" 2>/dev/null || echo 0)

        add_diagnostic "Session $SESSION_ID: ${SIZE_KB}KB, ${MARKERS} markers"

        if [ "$SIZE" -gt "$MAX_SESSION_BYTES" ] 2>/dev/null; then
            log_critical "Bloated session: $SESSION_ID (${SIZE_MB}MB)"
            BLOATED_SESSIONS+=("$SESSION_ID")
        elif [ "$MARKERS" -gt "$MAX_INJECTION_MARKERS" ] 2>/dev/null; then
            log_critical "Injection overload: $SESSION_ID (${MARKERS} markers)"
            BLOATED_SESSIONS+=("$SESSION_ID")
        elif [ "$SIZE_KB" -gt "$((WARN_SESSION_MB * 1024))" ] 2>/dev/null; then
            log_warn "Session growing: $SESSION_ID (${SIZE_KB}KB)"
        elif [ "$MARKERS" -gt "$WARN_INJECTION_MARKERS" ] 2>/dev/null; then
            log_warn "Injection count rising: $SESSION_ID (${MARKERS} markers)"
        fi
    done

    log_ok "Total: $TOTAL_SESSIONS sessions, ${TOTAL_SIZE_KB}KB"
}

check_recent_errors() {
    log_header "Recent Errors"
    add_diagnostic "=== RECENT ERRORS ==="

    TODAY=$(date +%Y-%m-%d)
    LOG_FILE="/tmp/openclaw/openclaw-$TODAY.log"

    if [ ! -f "$LOG_FILE" ]; then
        log_info "No log file for today"
        return
    fi

    RATE_ERRORS=$(grep -c "rate_limit\|cooldown\|too large\|overflow" "$LOG_FILE" 2>/dev/null || echo 0)
    add_diagnostic "Rate limit errors (today): $RATE_ERRORS"

    if [ "$RATE_ERRORS" -gt 10 ] 2>/dev/null; then
        log_critical "Many rate limit errors: $RATE_ERRORS today"
    elif [ "$RATE_ERRORS" -gt 2 ] 2>/dev/null; then
        log_warn "Rate limit errors detected: $RATE_ERRORS"
    else
        log_ok "Rate limit errors: $RATE_ERRORS"
    fi

    OVERFLOW=$(grep -c "overflow\|too large" "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "$OVERFLOW" -gt 0 ] 2>/dev/null; then
        log_critical "Context overflow errors: $OVERFLOW"
        add_diagnostic "Context overflow errors: $OVERFLOW"
    fi
}

save_diagnostics() {
    local reason="$1"
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local diag_file="$BUMP_LOG_DIR/bump-$(date +%Y%m%d-%H%M%S).md"

    mkdir -p "$BUMP_LOG_DIR"

    cat > "$diag_file" << EOF
# Surgery Diagnostic Report

**Timestamp:** $timestamp
**Trigger:** $reason
**Mode:** $([ "$SELF_BUMP" = true ] && echo "Self-bump" || echo "Manual")

## Problems Detected

$(for p in "${CRITICAL_PROBLEMS[@]}"; do echo "- CRITICAL: $p"; done)
$(for w in "${WARNINGS[@]}"; do echo "- WARNING: $w"; done)

## Diagnostics

$(echo -e "$DIAGNOSTICS")

## Session Snapshot

$(ls -lh "$SESSIONS_DIR"/*.jsonl 2>/dev/null | head -10)

---
*OCTO Surgery v3.0*
EOF

    echo "$diag_file"
}

write_notification() {
    local reason="$1"
    local diag_file="$2"
    local timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    cat > "$WATCHDOG_NOTIFY" << EOF
# Surgery Notification

**YOU WERE BUMPED**

**When:** $timestamp
**Reason:** $reason
**Mode:** $([ "$SELF_BUMP" = true ] && echo "Self-initiated" || echo "Manual")

## What Happened

$(for p in "${CRITICAL_PROBLEMS[@]}"; do echo "- $p"; done)

## Diagnostic Report

$diag_file

## Next Steps

1. Read the diagnostic report
2. Analyze what led to this bump
3. Check for patterns
4. Run 'octo doctor' for current health

---
*Delete this file after processing.*
EOF

    echo "$WATCHDOG_NOTIFY"
}

do_bump() {
    local reason="${1:-Unknown}"

    # Save diagnostics
    local diag_file=""
    if [ "$SELF_BUMP" = true ]; then
        diag_file=$(save_diagnostics "$reason")
        echo "Diagnostics saved: $diag_file"
    fi

    local archive_dir="$OPENCLAW_HOME/workspace/session-archives/surgery/$(date +%Y-%m-%d)"
    mkdir -p "$archive_dir"

    # Archive bloated sessions
    for f in "$SESSIONS_DIR"/*.jsonl; do
        [ -f "$f" ] || continue
        [[ "$(basename "$f")" == "sessions.json" ]] && continue
        [[ "$f" == *".archived."* ]] && continue

        if [[ "$OSTYPE" == "darwin"* ]]; then
            SIZE=$(stat -f%z "$f" 2>/dev/null || echo 0)
        else
            SIZE=$(stat -c%s "$f" 2>/dev/null || echo 0)
        fi

        MARKERS=$(grep -c "INJECTION-DEPTH" "$f" 2>/dev/null || echo 0)

        SHOULD_ARCHIVE=false
        if [ "$SIZE" -gt "$MAX_SESSION_BYTES" ] 2>/dev/null; then
            SHOULD_ARCHIVE=true
        elif [ "$MARKERS" -gt "$MAX_INJECTION_MARKERS" ] 2>/dev/null; then
            SHOULD_ARCHIVE=true
        fi

        if [ "$SHOULD_ARCHIVE" = true ]; then
            FILENAME=$(basename "$f")
            echo "  Archiving: $FILENAME"
            mv "$f" "$archive_dir/"
        fi
    done

    # Restart gateway
    if [ "$GATEWAY_RUNNING" = true ]; then
        echo "  Stopping gateway..."
        pkill -f openclaw-gateway 2>/dev/null || true
        sleep 2
        if pgrep -f openclaw-gateway > /dev/null 2>&1; then
            pkill -9 -f openclaw-gateway 2>/dev/null || true
            sleep 1
        fi
    fi

    echo "  Waiting ${RATE_LIMIT_COOLDOWN}s for cooldown..."
    sleep "$RATE_LIMIT_COOLDOWN"

    echo "  Starting gateway..."
    cd "$OPENCLAW_HOME"
    nohup openclaw gateway start > /tmp/gateway.log 2>&1 &
    sleep 5

    # Write notification
    if [ "$SELF_BUMP" = true ]; then
        local notify_path=$(write_notification "$reason" "$diag_file")
        echo "  Notification written: $notify_path"
    fi

    NEW_PID=$(pgrep -f openclaw-gateway | head -1 || true)
    if [ -n "$NEW_PID" ]; then
        echo "  Gateway started: PID $NEW_PID"
    else
        echo "  ERROR: Failed to start gateway!"
        return 1
    fi
}

show_summary() {
    echo
    echo "=============================================="
    echo -e "${BOLD}  HEALTH CHECK SUMMARY${NC}"
    echo "=============================================="

    if [ ${#CRITICAL_PROBLEMS[@]} -eq 0 ] && [ ${#WARNINGS[@]} -eq 0 ]; then
        echo
        echo -e "  ${GREEN}${BOLD}✓ ALL HEALTHY${NC}"
        echo
        return 0
    fi

    if [ ${#CRITICAL_PROBLEMS[@]} -gt 0 ]; then
        echo
        echo -e "  ${RED}${BOLD}CRITICAL (${#CRITICAL_PROBLEMS[@]})${NC}"
        for p in "${CRITICAL_PROBLEMS[@]}"; do
            echo -e "    ${RED}•${NC} $p"
        done
    fi

    if [ ${#WARNINGS[@]} -gt 0 ]; then
        echo
        echo -e "  ${YELLOW}${BOLD}WARNINGS (${#WARNINGS[@]})${NC}"
        for w in "${WARNINGS[@]}"; do
            echo -e "    ${YELLOW}•${NC} $w"
        done
    fi

    echo
    return 1
}

# Main
main() {
    echo "=============================================="
    echo -e "${BOLD}  OCTO Surgery v3.0${NC}"
    echo "=============================================="

    check_prerequisites
    check_gateway
    check_sessions
    check_recent_errors

    show_summary
    NEEDS_BUMP=$?

    # No problems
    if [ "$NEEDS_BUMP" -eq 0 ]; then
        [ "$CHECK_ONLY" = true ] && exit 0
        if [ "$AUTO_CONFIRM" != true ]; then
            echo -n "  Restart gateway anyway? [y/N] "
            read -r REPLY
            [[ ! $REPLY =~ ^[Yy]$ ]] && exit 0
        else
            exit 0
        fi
    fi

    # Check only mode
    if [ "$CHECK_ONLY" = true ]; then
        echo "  Run with -y to auto-fix or --self for self-bump"
        exit 0
    fi

    # Confirm bump
    if [ "$AUTO_CONFIRM" != true ]; then
        echo -n "  Proceed with surgery? [y/N] "
        read -r REPLY
        [[ ! $REPLY =~ ^[Yy]$ ]] && echo "  Aborted." && exit 0
    fi

    # Execute bump
    REASON=$(IFS='; '; echo "${CRITICAL_PROBLEMS[*]:-Manual bump}")
    do_bump "$REASON"

    echo
    echo -e "  ${GREEN}${BOLD}SURGERY COMPLETE${NC}"
}

main "$@"
