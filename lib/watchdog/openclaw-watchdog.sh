#!/usr/bin/env bash
#
# OCTO OpenClaw Watchdog
# Health monitoring and auto-recovery service
#
# Runs every minute (typically via cron), checks health, auto-bumps if critical
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OCTO_HOME="${OCTO_HOME:-$HOME/.octo}"
OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"

LOG="${OCTO_HOME}/logs/watchdog.log"
LOCK="/tmp/octo-watchdog.lock"
NOTIFY_FILE="$OPENCLAW_HOME/workspace/.watchdog-bump-notice"

# Thresholds
MAX_SESSION_SIZE_MB=10
OVERFLOW_ERROR_THRESHOLD=3

# Prevent concurrent runs
mkdir -p "$(dirname "$LOG")"
exec 200>"$LOCK"
flock -n 200 || exit 0

log() {
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $1" >> "$LOG"
}

# Quick health check - only critical issues
check_critical() {
    # 1. Gateway running?
    if ! pgrep -f openclaw-gateway > /dev/null 2>&1; then
        echo "Gateway not running"
        return 1
    fi

    # 2. Any session > threshold?
    local sessions_dir="$OPENCLAW_HOME/agents/main/sessions"
    if [ -d "$sessions_dir" ]; then
        for f in "$sessions_dir"/*.jsonl; do
            [ -f "$f" ] || continue
            [[ "$f" == *".archived."* ]] && continue
            [[ "$(basename "$f")" == "sessions.json" ]] && continue

            if [[ "$OSTYPE" == "darwin"* ]]; then
                local size=$(stat -f%z "$f" 2>/dev/null || echo 0)
            else
                local size=$(stat -c%s "$f" 2>/dev/null || echo 0)
            fi

            local max_size=$((MAX_SESSION_SIZE_MB * 1024 * 1024))
            if [ "$size" -gt "$max_size" ] 2>/dev/null; then
                echo "Bloated session: $(basename $f) ($((size/1024/1024))MB)"
                return 1
            fi
        done
    fi

    # 3. Recent overflow errors?
    local today=$(date +%Y-%m-%d)
    local log_file="/tmp/openclaw/openclaw-${today}.log"
    if [ -f "$log_file" ]; then
        local overflow=$(tail -200 "$log_file" 2>/dev/null | grep -c "overflow\|All models failed" || echo 0)
        if [ "$overflow" -gt "$OVERFLOW_ERROR_THRESHOLD" ] 2>/dev/null; then
            echo "Multiple overflow/failure errors: $overflow"
            return 1
        fi
    fi

    return 0
}

do_bump() {
    local reason="$1"

    log "CRITICAL: $reason - initiating bump"

    # Archive bloated sessions
    local sessions_dir="$OPENCLAW_HOME/agents/main/sessions"
    local archive_dir="$OPENCLAW_HOME/workspace/session-archives/watchdog/$(date +%Y-%m-%d)"
    mkdir -p "$archive_dir"

    if [ -d "$sessions_dir" ]; then
        for f in "$sessions_dir"/*.jsonl; do
            [ -f "$f" ] || continue
            [[ "$(basename "$f")" == "sessions.json" ]] && continue
            [[ "$f" == *".archived."* ]] && continue

            if [[ "$OSTYPE" == "darwin"* ]]; then
                local size=$(stat -f%z "$f" 2>/dev/null || echo 0)
            else
                local size=$(stat -c%s "$f" 2>/dev/null || echo 0)
            fi

            local max_size=$((MAX_SESSION_SIZE_MB * 1024 * 1024))
            if [ "$size" -gt "$max_size" ] 2>/dev/null; then
                local basename=$(basename "$f")
                log "Archiving bloated session: $basename"
                mv "$f" "$archive_dir/"
            fi
        done
    fi

    # Restart gateway
    log "Stopping gateway..."
    pkill -f openclaw-gateway 2>/dev/null || true
    sleep 2

    if pgrep -f openclaw-gateway > /dev/null 2>&1; then
        pkill -9 -f openclaw-gateway 2>/dev/null || true
        sleep 1
    fi

    log "Starting gateway..."
    cd "$OPENCLAW_HOME"
    nohup openclaw gateway start > /tmp/gateway.log 2>&1 &
    sleep 5

    # Write notification
    cat > "$NOTIFY_FILE" << EOF
# Watchdog Bump Notification

**When:** $(date -u +%Y-%m-%dT%H:%M:%SZ)
**Reason:** $reason

## Action Taken

- Bloated sessions archived to: $archive_dir
- Gateway restarted

## Next Steps

1. Review archived sessions
2. Check for patterns causing bloat
3. Run 'octo doctor' for full health check

---
*OCTO Watchdog*
EOF

    local new_pid=$(pgrep -f openclaw-gateway | head -1 || true)
    if [ -n "$new_pid" ]; then
        log "Gateway started: PID $new_pid"
    else
        log "ERROR: Failed to start gateway!"
    fi

    log "Bump complete"
}

show_status() {
    echo "=== OCTO Watchdog Status ==="
    echo ""
    echo "Configuration:"
    echo "  Max session size:       ${MAX_SESSION_SIZE_MB}MB"
    echo "  Overflow error limit:   $OVERFLOW_ERROR_THRESHOLD"
    echo "  Log file:               $LOG"
    echo ""

    echo "Current health check:"
    local problem=$(check_critical)
    if [ $? -eq 0 ]; then
        echo -e "  Status: \033[0;32mHEALTHY\033[0m"
    else
        echo -e "  Status: \033[0;31mCRITICAL\033[0m - $problem"
    fi

    echo ""
    echo "Recent log entries:"
    if [ -f "$LOG" ]; then
        tail -10 "$LOG" | sed 's/^/  /'
    else
        echo "  (no log file)"
    fi
}

install_cron() {
    local cron_entry="* * * * * $0 --cron"

    # Check if already installed
    if crontab -l 2>/dev/null | grep -q "octo.*watchdog"; then
        echo "Watchdog cron already installed"
        return
    fi

    # Add to crontab
    (crontab -l 2>/dev/null || true; echo "$cron_entry") | crontab -
    echo "Watchdog cron installed (runs every minute)"
}

uninstall_cron() {
    crontab -l 2>/dev/null | grep -v "octo.*watchdog" | crontab -
    echo "Watchdog cron removed"
}

# Main
case "${1:-}" in
    --cron)
        # Cron mode: check and bump if needed
        PROBLEM=$(check_critical)
        if [ $? -ne 0 ]; then
            do_bump "$PROBLEM"
        else
            # Heartbeat every 10 minutes
            MINUTE=$(date +%M)
            if [ "$((MINUTE % 10))" -eq 0 ]; then
                log "Heartbeat: healthy"
            fi
        fi
        ;;
    status)
        show_status
        ;;
    install)
        install_cron
        ;;
    uninstall)
        uninstall_cron
        ;;
    check)
        PROBLEM=$(check_critical)
        if [ $? -eq 0 ]; then
            echo "Health check: OK"
            exit 0
        else
            echo "Health check: CRITICAL - $PROBLEM"
            exit 1
        fi
        ;;
    *)
        echo "OCTO OpenClaw Watchdog"
        echo ""
        echo "Usage: octo watchdog {status|check|install|uninstall}"
        echo ""
        echo "Commands:"
        echo "  status      Show watchdog status and health"
        echo "  check       Run health check (exit 0=ok, 1=critical)"
        echo "  install     Install cron job (runs every minute)"
        echo "  uninstall   Remove cron job"
        echo ""
        echo "The watchdog monitors OpenClaw health and auto-recovers from:"
        echo "  - Gateway not running"
        echo "  - Bloated sessions (>${MAX_SESSION_SIZE_MB}MB)"
        echo "  - Repeated overflow errors"
        ;;
esac
