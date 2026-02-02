#!/usr/bin/env bash
#
# OCTO Bloat Sentinel v3.0
# Multi-layer session bloat detection and intervention
#
# DESIGN PRINCIPLE: Never destroy context without definitive proof of bloat
#
# Detection Layers:
#   Layer 1: Nested injection BLOCKS in single message (DEFINITIVE)
#   Layer 2: Rapid growth WITH injection markers (STRONG)
#   Layer 3: Size >10MB WITH multiple markers (MODERATE)
#   Layer 4: Total markers >10 (MONITOR ONLY)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OCTO_HOME="${OCTO_HOME:-$HOME/.octo}"
OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"

# Configuration
SESSIONS_DIR="$OPENCLAW_HOME/agents/main/sessions"
INTERVENTION_LOG_DIR="$OPENCLAW_HOME/workspace/intervention_logs"
SENTINEL_PID_FILE="/var/run/bloat-sentinel.pid"
SENTINEL_LOG="${OCTO_HOME}/logs/bloat-sentinel.log"

# Layer thresholds - tuned to avoid false positives
LAYER1_NESTED_BLOCKS=1           # >1 actual injection BLOCKS in single message
LAYER2_GROWTH_KB=1000            # 1MB growth
LAYER2_GROWTH_WINDOW=60          # Seconds
LAYER2_REQUIRE_MARKERS=true      # Only trigger growth check if markers present
LAYER3_MAX_SIZE_KB=10240         # 10MB
LAYER3_MIN_MARKERS=2             # Require multiple markers
LAYER4_TOTAL_MARKERS=10          # Monitor only

CHECK_INTERVAL=10

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

declare -A size_history

log() {
    local level="$1"
    shift
    local msg="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    mkdir -p "$(dirname "$SENTINEL_LOG")"
    echo "[$timestamp] [$level] $msg" >> "$SENTINEL_LOG"

    if [ -t 1 ]; then
        case "$level" in
            ALERT)   echo -e "${RED}[$level]${NC} $msg" ;;
            WARN)    echo -e "${YELLOW}[$level]${NC} $msg" ;;
            INFO)    echo -e "${GREEN}[$level]${NC} $msg" ;;
            MONITOR) echo -e "${CYAN}[$level]${NC} $msg" ;;
            *)       echo "[$level] $msg" ;;
        esac
    fi
}

# Count actual injection BLOCKS, not just marker text mentions
count_injection_blocks_in_message() {
    local content="$1"
    echo "$content" | grep -oP '\[INJECTION-DEPTH:[^\]]*\].{0,200}Recovered Conversation Context' 2>/dev/null | wc -l | tr -d ' '
}

# Get max injection blocks in any single user message
get_max_nested_blocks() {
    local session_file="$1"
    local max=0

    while IFS= read -r content; do
        local count=$(count_injection_blocks_in_message "$content")
        [ -z "$count" ] && count=0
        [ "$count" -gt "$max" ] && max=$count
    done < <(jq -r 'select(.type=="message" and .message.role=="user") | .message.content | tostring' "$session_file" 2>/dev/null)

    echo "$max"
}

# Count total injection blocks across all user messages
get_total_injection_blocks() {
    local session_file="$1"
    local total=0

    while IFS= read -r content; do
        local count=$(count_injection_blocks_in_message "$content")
        [ -z "$count" ] && count=0
        total=$((total + count))
    done < <(jq -r 'select(.type=="message" and .message.role=="user") | .message.content | tostring' "$session_file" 2>/dev/null)

    echo "$total"
}

create_intervention_log() {
    local layer="$1"
    local reason="$2"
    local session_file="$3"

    mkdir -p "$INTERVENTION_LOG_DIR"
    local timestamp=$(date '+%Y%m%d-%H%M%S')
    local basename=$(basename "$session_file")
    local log_file="$INTERVENTION_LOG_DIR/intervention-$timestamp.md"
    local session_copy="$INTERVENTION_LOG_DIR/${timestamp}-${basename}"

    cp "$session_file" "$session_copy"

    local file_size=$(du -h "$session_file" 2>/dev/null | cut -f1)
    local line_count=$(wc -l < "$session_file")
    local max_nested=$(get_max_nested_blocks "$session_file")
    local total_blocks=$(get_total_injection_blocks "$session_file")

    cat > "$log_file" << EOF
# Bloat Sentinel Intervention

**Timestamp:** $(date -Iseconds)
**Detection Layer:** $layer
**Reason:** $reason
**Session:** $basename
**Session Copy:** ${timestamp}-${basename}

## Session Analysis

- **File size:** $file_size
- **Lines:** $line_count
- **Max nested blocks:** $max_nested
- **Total injection blocks:** $total_blocks

## Action Taken

Original session preserved at: $session_copy
Session cleaned in-place (if valid cleaner output)
Gateway restarted

---
*OCTO Bloat Sentinel v3.0*
EOF

    log INFO "Intervention log: $log_file"
    echo "$log_file"
}

clean_and_restart() {
    local session_file="$1"
    local layer="$2"
    local reason="$3"
    local basename=$(basename "$session_file")

    log ALERT "LAYER $layer INTERVENTION: $reason"

    # Create intervention log
    create_intervention_log "$layer" "$reason" "$session_file"

    # Archive the bloated session
    local archive_dir="$OPENCLAW_HOME/workspace/session-archives/bloated/$(date +%Y-%m-%d)"
    mkdir -p "$archive_dir"

    local archive_name="${basename%.jsonl}.$(date +%H%M%S).jsonl"
    cp "$session_file" "$archive_dir/$archive_name"
    log INFO "Session archived to $archive_dir/$archive_name"

    # Clear the session file (keep structure)
    echo '{"type":"session_start","timestamp":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"}' > "$session_file"
    log INFO "Session file reset"

    # Restart gateway
    log INFO "Restarting gateway..."
    pkill -f openclaw-gateway 2>/dev/null || true
    sleep 2

    cd "$OPENCLAW_HOME" && nohup openclaw gateway start > /tmp/gateway.log 2>&1 &

    sleep 3
    if pgrep -f openclaw-gateway >/dev/null 2>&1; then
        log INFO "Gateway restarted - intervention complete"
    else
        log ALERT "Gateway failed to restart!"
    fi

    size_history[$basename]=""
}

# Layer 1: Check for nested injection BLOCKS
check_layer1_nested() {
    local session_file="$1"
    local basename=$(basename "$session_file")

    local max_nested=$(get_max_nested_blocks "$session_file")
    [ -z "$max_nested" ] && max_nested=0

    if [ "$max_nested" -gt "$LAYER1_NESTED_BLOCKS" ]; then
        clean_and_restart "$session_file" "1 (Nested Blocks)" \
            "Single message has $max_nested injection blocks - feedback loop confirmed"
        return 1
    fi
    return 0
}

# Layer 2: Rapid growth with markers
check_layer2_growth() {
    local session_file="$1"
    local basename=$(basename "$session_file")

    # Get file size based on OS
    if [[ "$OSTYPE" == "darwin"* ]]; then
        local current_size=$(stat -f%z "$session_file" 2>/dev/null | tr -d ' ' || echo 0)
    else
        local current_size=$(stat -c%s "$session_file" 2>/dev/null | tr -d ' ' || echo 0)
    fi

    local current_size_kb=$((current_size / 1024))
    local current_time=$(date +%s)

    [ -z "$current_size_kb" ] && return 0

    local history="${size_history[$basename]:-}"

    if [ -n "$history" ]; then
        history="$history,$current_time:$current_size_kb"
    else
        history="$current_time:$current_size_kb"
    fi

    local cutoff=$((current_time - LAYER2_GROWTH_WINDOW))
    local new_history=""
    local oldest_size_in_window=""
    local oldest_time_in_window=""

    IFS=',' read -ra entries <<< "$history"
    for entry in "${entries[@]}"; do
        local t="${entry%%:*}"
        local s="${entry##*:}"
        if [ "$t" -ge "$cutoff" ]; then
            if [ -z "$new_history" ]; then
                new_history="$entry"
                oldest_size_in_window="$s"
                oldest_time_in_window="$t"
            else
                new_history="$new_history,$entry"
            fi
        fi
    done

    size_history[$basename]="$new_history"

    if [ -n "$oldest_size_in_window" ] && [ "$oldest_time_in_window" -lt "$current_time" ]; then
        local growth=$((current_size_kb - oldest_size_in_window))
        local elapsed=$((current_time - oldest_time_in_window))

        if [ "$growth" -gt "$LAYER2_GROWTH_KB" ]; then
            if [ "$LAYER2_REQUIRE_MARKERS" = true ]; then
                local total_blocks=$(get_total_injection_blocks "$session_file")
                [ -z "$total_blocks" ] && total_blocks=0

                if [ "$total_blocks" -gt 0 ]; then
                    clean_and_restart "$session_file" "2 (Rapid Growth + Markers)" \
                        "Session grew ${growth}KB in ${elapsed}s with $total_blocks injection blocks"
                    return 1
                else
                    log MONITOR "Layer 2: $basename grew ${growth}KB in ${elapsed}s but has no injection blocks - likely legitimate"
                fi
            else
                clean_and_restart "$session_file" "2 (Rapid Growth)" \
                    "Session grew ${growth}KB in ${elapsed}s"
                return 1
            fi
        fi
    fi
    return 0
}

# Layer 3: Size limit with markers
check_layer3_size() {
    local session_file="$1"
    local basename=$(basename "$session_file")

    if [[ "$OSTYPE" == "darwin"* ]]; then
        local size_kb=$(( $(stat -f%z "$session_file" 2>/dev/null || echo 0) / 1024 ))
    else
        local size_kb=$(( $(stat -c%s "$session_file" 2>/dev/null || echo 0) / 1024 ))
    fi

    [ -z "$size_kb" ] && return 0

    if [ "$size_kb" -gt "$LAYER3_MAX_SIZE_KB" ]; then
        local total_blocks=$(get_total_injection_blocks "$session_file")
        [ -z "$total_blocks" ] && total_blocks=0

        if [ "$total_blocks" -ge "$LAYER3_MIN_MARKERS" ]; then
            clean_and_restart "$session_file" "3 (Size + Multiple Markers)" \
                "Session is ${size_kb}KB with $total_blocks injection blocks"
            return 1
        else
            log MONITOR "Layer 3: $basename is ${size_kb}KB with only $total_blocks blocks - legitimate large session"
        fi
    fi
    return 0
}

# Layer 4: Total markers (monitor only)
check_layer4_total() {
    local session_file="$1"
    local basename=$(basename "$session_file")

    local total_blocks=$(get_total_injection_blocks "$session_file")
    [ -z "$total_blocks" ] && total_blocks=0

    if [ "$total_blocks" -gt "$LAYER4_TOTAL_MARKERS" ]; then
        log MONITOR "Layer 4: $basename has $total_blocks injection blocks (threshold: $LAYER4_TOTAL_MARKERS)"
    fi
    return 0
}

check_session() {
    local session_file="$1"
    local basename=$(basename "$session_file")

    [[ "$basename" == "sessions.json" ]] && return 0
    [ ! -f "$session_file" ] && return 0

    check_layer1_nested "$session_file" || return 1
    check_layer2_growth "$session_file" || return 1
    check_layer3_size "$session_file" || return 1
    check_layer4_total "$session_file"

    return 0
}

monitor_loop() {
    log INFO "OCTO Bloat Sentinel v3.0 started"
    log INFO "Layer 1: Nested injection BLOCKS >$LAYER1_NESTED_BLOCKS in single message"
    log INFO "Layer 2: Growth >${LAYER2_GROWTH_KB}KB in ${LAYER2_GROWTH_WINDOW}s (requires markers: $LAYER2_REQUIRE_MARKERS)"
    log INFO "Layer 3: Size >${LAYER3_MAX_SIZE_KB}KB with >=$LAYER3_MIN_MARKERS blocks"
    log INFO "Layer 4: Total blocks >$LAYER4_TOTAL_MARKERS (MONITOR ONLY)"
    log INFO "Monitoring: $SESSIONS_DIR"

    while true; do
        if ! pgrep -f openclaw-gateway >/dev/null 2>&1; then
            sleep 30
            continue
        fi

        shopt -s nullglob
        for f in "$SESSIONS_DIR"/*.jsonl; do
            check_session "$f" || true
        done

        sleep "$CHECK_INTERVAL"
    done
}

show_status() {
    echo "=== OCTO Bloat Sentinel v3.0 Status ==="
    echo ""

    if [ -f "$SENTINEL_PID_FILE" ]; then
        local pid=$(cat "$SENTINEL_PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo -e "Status: ${GREEN}RUNNING${NC} (PID $pid)"
        else
            echo -e "Status: ${RED}DEAD${NC} (stale PID $pid)"
        fi
    else
        echo -e "Status: ${YELLOW}NOT RUNNING${NC}"
    fi

    echo ""
    echo "Detection Layers:"
    echo "  Layer 1: Nested injection BLOCKS >$LAYER1_NESTED_BLOCKS (DEFINITIVE)"
    echo "  Layer 2: Growth >${LAYER2_GROWTH_KB}KB in ${LAYER2_GROWTH_WINDOW}s with markers (STRONG)"
    echo "  Layer 3: Size >${LAYER3_MAX_SIZE_KB}KB with >=$LAYER3_MIN_MARKERS blocks (MODERATE)"
    echo "  Layer 4: Total blocks >$LAYER4_TOTAL_MARKERS (MONITOR ONLY)"

    echo ""
    echo "Recent interventions:"
    if [ -d "$INTERVENTION_LOG_DIR" ]; then
        local count=$(ls -1 "$INTERVENTION_LOG_DIR"/intervention-*.md 2>/dev/null | wc -l)
        if [ "$count" -gt 0 ]; then
            ls -lt "$INTERVENTION_LOG_DIR"/intervention-*.md 2>/dev/null | head -5 | while read -r line; do
                echo "  $line"
            done
        else
            echo "  (none)"
        fi
    else
        echo "  (no intervention log directory)"
    fi

    echo ""
    echo "Current sessions:"
    if [ -d "$SESSIONS_DIR" ]; then
        shopt -s nullglob
        for f in "$SESSIONS_DIR"/*.jsonl; do
            [ -f "$f" ] || continue
            local bn=$(basename "$f")
            [[ "$bn" == "sessions.json" ]] && continue

            if [[ "$OSTYPE" == "darwin"* ]]; then
                local size=$(( $(stat -f%z "$f" 2>/dev/null || echo 0) / 1024 ))
            else
                local size=$(( $(stat -c%s "$f" 2>/dev/null || echo 0) / 1024 ))
            fi

            local max_nested=$(get_max_nested_blocks "$f")
            [ -z "$max_nested" ] && max_nested=0

            local total=$(get_total_injection_blocks "$f")
            [ -z "$total" ] && total=0

            local status="OK"
            local color="$GREEN"

            if [ "$max_nested" -gt "$LAYER1_NESTED_BLOCKS" ]; then
                status="L1:NESTED!"
                color="$RED"
            elif [ "$size" -gt "$LAYER3_MAX_SIZE_KB" ] && [ "$total" -ge "$LAYER3_MIN_MARKERS" ]; then
                status="L3:SIZE+MARKERS!"
                color="$RED"
            elif [ "$total" -gt "$LAYER4_TOTAL_MARKERS" ]; then
                status="L4:monitor"
                color="$YELLOW"
            fi

            printf "  %-45s %6dKB  nested:%d total:%d  ${color}%s${NC}\n" \
                "$bn" "$size" "$max_nested" "$total" "$status"
        done
    fi
}

start_daemon() {
    if [ -f "$SENTINEL_PID_FILE" ]; then
        local old_pid=$(cat "$SENTINEL_PID_FILE")
        if kill -0 "$old_pid" 2>/dev/null; then
            echo "Sentinel already running (PID $old_pid)"
            exit 1
        fi
        rm "$SENTINEL_PID_FILE"
    fi

    mkdir -p "$(dirname "$SENTINEL_PID_FILE")" "$(dirname "$SENTINEL_LOG")" "$INTERVENTION_LOG_DIR" 2>/dev/null || true

    nohup "$0" start >> "$SENTINEL_LOG" 2>&1 &
    echo "$!" > "$SENTINEL_PID_FILE"
    echo "OCTO Bloat Sentinel v3.0 started (PID $!)"
    echo "Log: $SENTINEL_LOG"
    echo "Interventions: $INTERVENTION_LOG_DIR"
}

stop_daemon() {
    if [ -f "$SENTINEL_PID_FILE" ]; then
        local pid=$(cat "$SENTINEL_PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid"
            rm "$SENTINEL_PID_FILE"
            echo "Sentinel stopped (was PID $pid)"
        else
            rm "$SENTINEL_PID_FILE"
            echo "Sentinel not running (stale PID removed)"
        fi
    else
        echo "Sentinel not running"
    fi
}

# Main
case "${1:-}" in
    start)   monitor_loop ;;
    daemon)  start_daemon ;;
    stop)    stop_daemon ;;
    status)  show_status ;;
    *)
        echo "OCTO Bloat Sentinel v3.0"
        echo ""
        echo "Usage: octo sentinel {start|daemon|stop|status}"
        echo ""
        echo "Commands:"
        echo "  daemon    Start sentinel as background daemon"
        echo "  start     Start sentinel in foreground"
        echo "  stop      Stop running sentinel"
        echo "  status    Show sentinel status and session health"
        exit 1
        ;;
esac
