#!/usr/bin/env bash
#
# OCTO Analyze Command
# Deep analysis of token usage patterns
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

# Parse arguments
PERIOD="today"
VERBOSE=false
SESSION_ID=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --period=*)
            PERIOD="${1#*=}"
            shift
            ;;
        --period)
            PERIOD="$2"
            shift 2
            ;;
        --session=*)
            SESSION_ID="${1#*=}"
            shift
            ;;
        --session)
            SESSION_ID="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            echo "Usage: octo analyze [options]"
            echo ""
            echo "Options:"
            echo "  --period=PERIOD    Analysis period: today, yesterday, week, month (default: today)"
            echo "  --session=ID       Analyze specific session"
            echo "  -v, --verbose      Show detailed breakdown"
            echo "  -h, --help         Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${NC}                    ${BOLD}OCTO Usage Analysis${NC}                          ${CYAN}║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"

# Load pricing
PRICING_FILE="$LIB_DIR/config/model_pricing.json"
if [ ! -f "$PRICING_FILE" ]; then
    echo -e "${RED}Error:${NC} Pricing file not found"
    exit 1
fi

# Analyze specific session
analyze_session() {
    local session_file="$1"
    local basename=$(basename "$session_file")
    local session_id="${basename%.jsonl}"

    echo ""
    echo -e "${BOLD}Session: ${session_id}${NC}"
    echo "────────────────────────────────────────────────────────────────────"

    if [ ! -f "$session_file" ]; then
        echo -e "  ${RED}Session file not found${NC}"
        return
    fi

    # File stats
    local size=$(stat -f%z "$session_file" 2>/dev/null || stat -c%s "$session_file" 2>/dev/null || echo 0)
    local size_kb=$((size / 1024))
    local lines=$(wc -l < "$session_file" | tr -d ' ')

    echo "  File size:              ${size_kb}KB"
    echo "  Total lines:            $lines"

    # Message counts
    local user_msgs=$(jq -c 'select(.type=="message" and .message.role=="user")' "$session_file" 2>/dev/null | wc -l | tr -d ' ')
    local assistant_msgs=$(jq -c 'select(.type=="message" and .message.role=="assistant")' "$session_file" 2>/dev/null | wc -l | tr -d ' ')

    echo "  User messages:          $user_msgs"
    echo "  Assistant messages:     $assistant_msgs"

    # Injection analysis
    local injection_count=$(grep -c "INJECTION-DEPTH" "$session_file" 2>/dev/null || echo 0)
    echo "  Injection markers:      $injection_count"

    if [ "$injection_count" -gt 10 ]; then
        echo -e "    ${YELLOW}⚠ High injection count - possible feedback loop${NC}"
    fi

    # Model usage (if verbose)
    if [ "$VERBOSE" = true ]; then
        echo ""
        echo "  Model usage:"
        local models=$(jq -r 'select(.type=="message" and .message.role=="assistant") | .model // "unknown"' "$session_file" 2>/dev/null | sort | uniq -c | sort -rn)
        if [ -n "$models" ]; then
            echo "$models" | while read -r count model; do
                printf "    %-20s %s requests\n" "$model:" "$count"
            done
        fi
    fi

    # Estimate tokens (rough)
    # Approx 4 chars per token
    local est_tokens=$((size / 4))
    echo ""
    echo "  Estimated tokens:       ~$est_tokens"

    # Cost estimate
    local sonnet_input=$(jq -r '.models["claude-sonnet-4-20250514"].input_per_million' "$PRICING_FILE")
    local est_cost=$(echo "scale=4; $est_tokens * $sonnet_input / 1000000" | bc 2>/dev/null || echo "N/A")
    echo "  Estimated cost:         \$$est_cost (input only, Sonnet rates)"
}

# Analyze all sessions
analyze_all() {
    local sessions_dir="$OPENCLAW_HOME/agents/main/sessions"

    if [ ! -d "$sessions_dir" ]; then
        echo -e "${YELLOW}No sessions directory found${NC}"
        return
    fi

    local total_sessions=0
    local total_size_kb=0
    local total_injections=0
    local bloated_sessions=0

    declare -A model_counts

    echo ""
    echo -e "${BOLD}Session Overview${NC}"
    echo "────────────────────────────────────────────────────────────────────"

    for f in "$sessions_dir"/*.jsonl; do
        [ -f "$f" ] || continue
        [[ "$(basename "$f")" == "sessions.json" ]] && continue
        [[ "$f" == *".archived."* ]] && continue

        total_sessions=$((total_sessions + 1))

        local size=$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f" 2>/dev/null || echo 0)
        local size_kb=$((size / 1024))
        total_size_kb=$((total_size_kb + size_kb))

        if [ "$size_kb" -gt 10240 ]; then
            bloated_sessions=$((bloated_sessions + 1))
        fi

        local markers=$(grep -c "INJECTION-DEPTH" "$f" 2>/dev/null || echo 0)
        total_injections=$((total_injections + markers))
    done

    echo "  Total active sessions:  $total_sessions"
    echo "  Total size:             ${total_size_kb}KB"
    echo "  Total injections:       $total_injections"

    if [ "$bloated_sessions" -gt 0 ]; then
        echo -e "  Bloated sessions:       ${RED}$bloated_sessions${NC}"
    else
        echo -e "  Bloated sessions:       ${GREEN}0${NC}"
    fi

    # Average session size
    if [ "$total_sessions" -gt 0 ]; then
        local avg_size=$((total_size_kb / total_sessions))
        echo "  Average session size:   ${avg_size}KB"
    fi
}

# Analyze cost files
analyze_costs() {
    local costs_dir="$OCTO_HOME/costs"

    if [ ! -d "$costs_dir" ]; then
        mkdir -p "$costs_dir"
    fi

    echo ""
    echo -e "${BOLD}Cost Analysis (Period: $PERIOD)${NC}"
    echo "────────────────────────────────────────────────────────────────────"

    case "$PERIOD" in
        today)
            local files=$(ls "$costs_dir/$(date +%Y-%m-%d).jsonl" 2>/dev/null || true)
            ;;
        yesterday)
            local files=$(ls "$costs_dir/$(date -d yesterday +%Y-%m-%d 2>/dev/null || date -v-1d +%Y-%m-%d).jsonl" 2>/dev/null || true)
            ;;
        week)
            local files=$(find "$costs_dir" -name "*.jsonl" -mtime -7 2>/dev/null | sort || true)
            ;;
        month)
            local files=$(find "$costs_dir" -name "*.jsonl" -mtime -30 2>/dev/null | sort || true)
            ;;
        *)
            echo -e "  ${RED}Unknown period: $PERIOD${NC}"
            return
            ;;
    esac

    if [ -z "$files" ]; then
        echo -e "  ${DIM}No cost data for this period${NC}"
        echo ""
        echo "  Cost tracking will collect data as you use OpenClaw."
        echo "  Check back after some usage to see analysis."
        return
    fi

    local total_cost=0
    local total_requests=0
    local total_input_tokens=0
    local total_output_tokens=0
    local total_cached_tokens=0

    for f in $files; do
        [ -f "$f" ] || continue

        local file_cost=$(jq -s 'map(.total // 0) | add // 0' "$f" 2>/dev/null || echo "0")
        local file_requests=$(wc -l < "$f" | tr -d ' ')
        local file_input=$(jq -s 'map(.input_tokens // 0) | add // 0' "$f" 2>/dev/null || echo "0")
        local file_output=$(jq -s 'map(.output_tokens // 0) | add // 0' "$f" 2>/dev/null || echo "0")
        local file_cached=$(jq -s 'map(.cache_read_tokens // 0) | add // 0' "$f" 2>/dev/null || echo "0")

        total_cost=$(echo "$total_cost + $file_cost" | bc 2>/dev/null || echo "$total_cost")
        total_requests=$((total_requests + file_requests))
        total_input_tokens=$((total_input_tokens + ${file_input%.*}))
        total_output_tokens=$((total_output_tokens + ${file_output%.*}))
        total_cached_tokens=$((total_cached_tokens + ${file_cached%.*}))
    done

    printf "  Total requests:         %d\n" "$total_requests"
    printf "  Total cost:             \$%.4f\n" "$total_cost"
    printf "  Input tokens:           %d\n" "$total_input_tokens"
    printf "  Output tokens:          %d\n" "$total_output_tokens"
    printf "  Cached tokens:          %d\n" "$total_cached_tokens"

    if [ "$total_requests" -gt 0 ]; then
        local avg_cost=$(echo "scale=4; $total_cost / $total_requests" | bc 2>/dev/null || echo "N/A")
        printf "  Avg cost/request:       \$%s\n" "$avg_cost"
    fi

    # Cache efficiency
    if [ "$total_input_tokens" -gt 0 ]; then
        local cache_pct=$((total_cached_tokens * 100 / (total_input_tokens + total_cached_tokens)))
        echo ""
        echo "  Cache efficiency:       ${cache_pct}%"

        if [ "$cache_pct" -lt 20 ]; then
            echo -e "    ${YELLOW}⚠ Low cache utilization - ensure caching is enabled${NC}"
        elif [ "$cache_pct" -gt 40 ]; then
            echo -e "    ${GREEN}✓ Good cache utilization${NC}"
        fi
    fi
}

# Savings estimate
estimate_savings() {
    echo ""
    echo -e "${BOLD}Savings Estimate${NC}"
    echo "────────────────────────────────────────────────────────────────────"

    # Load config to see what's enabled
    if [ -f "$OCTO_HOME/config.json" ]; then
        local caching=$(jq -r '.optimization.promptCaching.enabled // false' "$OCTO_HOME/config.json")
        local tiering=$(jq -r '.optimization.modelTiering.enabled // false' "$OCTO_HOME/config.json")
        local onelist=$(jq -r '.onelist.installed // false' "$OCTO_HOME/config.json")

        local savings_low=0
        local savings_high=0

        if [ "$caching" = "true" ]; then
            echo -e "  Prompt Caching:         ${GREEN}enabled${NC} (+25-40% savings)"
            savings_low=$((savings_low + 25))
            savings_high=$((savings_high + 40))
        else
            echo -e "  Prompt Caching:         ${DIM}disabled${NC}"
        fi

        if [ "$tiering" = "true" ]; then
            echo -e "  Model Tiering:          ${GREEN}enabled${NC} (+20-35% savings)"
            savings_low=$((savings_low + 20))
            savings_high=$((savings_high + 35))
        else
            echo -e "  Model Tiering:          ${DIM}disabled${NC}"
        fi

        if [ "$onelist" = "true" ]; then
            echo -e "  Onelist Memory:         ${GREEN}enabled${NC} (+50-70% savings)"
            savings_low=$((savings_low + 50))
            savings_high=$((savings_high + 70))
        else
            echo -e "  Onelist Memory:         ${DIM}not installed${NC}"
        fi

        # Cap estimates
        [ "$savings_high" -gt 95 ] && savings_high=95
        [ "$savings_low" -gt 90 ] && savings_low=90

        echo ""
        echo -e "  ${BOLD}Estimated total savings: ${GREEN}${savings_low}-${savings_high}%${NC}"

        if [ "$onelist" != "true" ]; then
            echo ""
            echo -e "  ${YELLOW}💡 Install Onelist for additional 50-70% savings${NC}"
            echo -e "     Run: octo onelist"
        fi
    else
        echo -e "  ${DIM}Configuration not found - run 'octo install'${NC}"
    fi
}

# Main
if [ -n "$SESSION_ID" ]; then
    # Analyze specific session
    session_file="$OPENCLAW_HOME/agents/main/sessions/${SESSION_ID}.jsonl"
    analyze_session "$session_file"
else
    # Full analysis
    analyze_all
    analyze_costs
    estimate_savings
fi

echo ""
