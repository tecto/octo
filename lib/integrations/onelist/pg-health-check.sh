#!/usr/bin/env bash
#
# OCTO PostgreSQL Health Check
# Database health monitoring and maintenance for Onelist
#
# Usage: octo pg-health [database_name]
#
# Exit codes:
#   0 = Healthy
#   1 = Warning (degraded but functional)
#   2 = Critical (requires immediate attention)
#

set -euo pipefail

# Configuration
DB_NAME="${1:-onelist_dev}"
DB_USER="${PGUSER:-postgres}"

# Thresholds
MAX_CONNECTIONS_WARN=80    # Percentage
MAX_CONNECTIONS_CRIT=95    # Percentage
CACHE_HIT_WARN=95          # Below this = warning
CACHE_HIT_CRIT=90          # Below this = critical
DEAD_TUPLE_WARN=10         # Percentage
DEAD_TUPLE_CRIT=30         # Percentage
XID_AGE_WARN=50            # Percentage of wraparound
XID_AGE_CRIT=75            # Percentage of wraparound
DISK_USAGE_WARN=70         # Percentage
DISK_USAGE_CRIT=85         # Percentage
LONG_QUERY_WARN=300        # Seconds (5 minutes)
LONG_QUERY_CRIT=1800       # Seconds (30 minutes)

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# Status tracking
EXIT_CODE=0
WARNINGS=()
CRITICALS=()

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; WARNINGS+=("$1"); [ $EXIT_CODE -lt 1 ] && EXIT_CODE=1; }
log_crit() { echo -e "${RED}[CRIT]${NC} $1"; CRITICALS+=("$1"); EXIT_CODE=2; }

run_query() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        psql -U "$DB_USER" -d "$DB_NAME" -t -A -c "$1" 2>/dev/null
    else
        sudo -u "$DB_USER" psql -d "$DB_NAME" -t -A -c "$1" 2>/dev/null
    fi
}

header() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${BLUE}  $1${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

check_postgres_running() {
    header "PostgreSQL Service Status"

    if command -v pg_isready &>/dev/null && pg_isready -q 2>/dev/null; then
        VERSION=$(run_query "SELECT version();" | head -1 | cut -d' ' -f1-2)
        log_ok "PostgreSQL is running: $VERSION"
    else
        log_crit "PostgreSQL is NOT running or not accepting connections"
        exit 2
    fi
}

check_connections() {
    header "Connection Health"

    MAX_CONN=$(run_query "SHOW max_connections;")
    CURRENT_CONN=$(run_query "SELECT count(*) FROM pg_stat_activity WHERE datname = '$DB_NAME';")
    ACTIVE_CONN=$(run_query "SELECT count(*) FROM pg_stat_activity WHERE datname = '$DB_NAME' AND state = 'active';")
    IDLE_CONN=$(run_query "SELECT count(*) FROM pg_stat_activity WHERE datname = '$DB_NAME' AND state = 'idle';")
    IDLE_TX=$(run_query "SELECT count(*) FROM pg_stat_activity WHERE datname = '$DB_NAME' AND state = 'idle in transaction';")

    CONN_PCT=$((CURRENT_CONN * 100 / MAX_CONN))

    echo "  Total: $CURRENT_CONN / $MAX_CONN ($CONN_PCT%)"
    echo "  Active: $ACTIVE_CONN | Idle: $IDLE_CONN | Idle in TX: $IDLE_TX"

    if [ "$CONN_PCT" -ge "$MAX_CONNECTIONS_CRIT" ]; then
        log_crit "Connection usage critical: ${CONN_PCT}%"
    elif [ "$CONN_PCT" -ge "$MAX_CONNECTIONS_WARN" ]; then
        log_warn "Connection usage elevated: ${CONN_PCT}%"
    else
        log_ok "Connection usage normal: ${CONN_PCT}%"
    fi

    if [ "$IDLE_TX" -gt 0 ]; then
        log_warn "Found $IDLE_TX idle-in-transaction connections"
    fi
}

check_cache() {
    header "Cache Hit Ratio"

    CACHE_RATIO=$(run_query "SELECT ROUND(100.0 * blks_hit / NULLIF(blks_read + blks_hit, 0), 2) FROM pg_stat_database WHERE datname = '$DB_NAME';")

    if [ -z "$CACHE_RATIO" ] || [ "$CACHE_RATIO" = "" ]; then
        log_warn "Could not determine cache hit ratio"
        return
    fi

    CACHE_INT=${CACHE_RATIO%.*}

    echo "  Cache hit ratio: ${CACHE_RATIO}%"

    if [ "$CACHE_INT" -lt "$CACHE_HIT_CRIT" ]; then
        log_crit "Cache hit ratio critically low: ${CACHE_RATIO}%"
    elif [ "$CACHE_INT" -lt "$CACHE_HIT_WARN" ]; then
        log_warn "Cache hit ratio below optimal: ${CACHE_RATIO}%"
    else
        log_ok "Cache hit ratio excellent: ${CACHE_RATIO}%"
    fi
}

check_vacuum() {
    header "Vacuum Status"

    TABLES_NEEDING_VACUUM=$(run_query "
        SELECT count(*) FROM pg_stat_user_tables
        WHERE n_dead_tup > 1000
        AND ROUND(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 2) > $DEAD_TUPLE_WARN;
    ")

    TABLES_CRITICAL=$(run_query "
        SELECT count(*) FROM pg_stat_user_tables
        WHERE n_dead_tup > 1000
        AND ROUND(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 2) > $DEAD_TUPLE_CRIT;
    ")

    WORST_TABLE=$(run_query "
        SELECT relname || ': ' || ROUND(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 2) || '% dead'
        FROM pg_stat_user_tables
        WHERE n_dead_tup > 100
        ORDER BY n_dead_tup DESC
        LIMIT 1;
    ")

    echo "  Tables needing vacuum (>$DEAD_TUPLE_WARN% dead): $TABLES_NEEDING_VACUUM"
    [ -n "$WORST_TABLE" ] && echo "  Worst table: $WORST_TABLE"

    if [ "$TABLES_CRITICAL" -gt 0 ]; then
        log_crit "$TABLES_CRITICAL tables with critical bloat (>${DEAD_TUPLE_CRIT}% dead tuples)"
    elif [ "$TABLES_NEEDING_VACUUM" -gt 0 ]; then
        log_warn "$TABLES_NEEDING_VACUUM tables need vacuum"
    else
        log_ok "All tables within vacuum thresholds"
    fi
}

check_xid() {
    header "Transaction ID Wraparound"

    XID_PCT=$(run_query "
        SELECT ROUND(100.0 * age(datfrozenxid) / 2147483647, 2)
        FROM pg_database WHERE datname = '$DB_NAME';
    ")

    if [ -z "$XID_PCT" ]; then
        log_warn "Could not determine XID age"
        return
    fi

    XID_INT=${XID_PCT%.*}

    echo "  XID age: ${XID_PCT}% toward wraparound"

    if [ "$XID_INT" -ge "$XID_AGE_CRIT" ]; then
        log_crit "XID wraparound imminent: ${XID_PCT}%"
    elif [ "$XID_INT" -ge "$XID_AGE_WARN" ]; then
        log_warn "XID age elevated: ${XID_PCT}%"
    else
        log_ok "XID age healthy: ${XID_PCT}%"
    fi
}

check_long_queries() {
    header "Long-Running Queries"

    LONG_QUERIES=$(run_query "
        SELECT count(*) FROM pg_stat_activity
        WHERE state = 'active'
        AND datname = '$DB_NAME'
        AND now() - query_start > interval '$LONG_QUERY_WARN seconds';
    ")

    VERY_LONG=$(run_query "
        SELECT count(*) FROM pg_stat_activity
        WHERE state = 'active'
        AND datname = '$DB_NAME'
        AND now() - query_start > interval '$LONG_QUERY_CRIT seconds';
    ")

    echo "  Queries > ${LONG_QUERY_WARN}s: $LONG_QUERIES"
    echo "  Queries > ${LONG_QUERY_CRIT}s: $VERY_LONG"

    if [ "$VERY_LONG" -gt 0 ]; then
        log_crit "$VERY_LONG queries running > 30 minutes"
    elif [ "$LONG_QUERIES" -gt 0 ]; then
        log_warn "$LONG_QUERIES queries running > 5 minutes"
    else
        log_ok "No long-running queries"
    fi
}

check_disk() {
    header "Disk Usage"

    DB_SIZE=$(run_query "SELECT pg_size_pretty(pg_database_size('$DB_NAME'));")
    PGDATA=$(run_query "SHOW data_directory;")
    DISK_PCT=$(df "$PGDATA" 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%')
    DISK_AVAIL=$(df -h "$PGDATA" 2>/dev/null | tail -1 | awk '{print $4}')

    echo "  Database size: $DB_SIZE"
    echo "  Disk usage: ${DISK_PCT}% (${DISK_AVAIL} available)"

    if [ "$DISK_PCT" -ge "$DISK_USAGE_CRIT" ]; then
        log_crit "Disk usage critical: ${DISK_PCT}%"
    elif [ "$DISK_PCT" -ge "$DISK_USAGE_WARN" ]; then
        log_warn "Disk usage elevated: ${DISK_PCT}%"
    else
        log_ok "Disk usage healthy: ${DISK_PCT}%"
    fi
}

check_locks() {
    header "Lock Status"

    BLOCKED=$(run_query "
        SELECT count(*) FROM pg_stat_activity
        WHERE wait_event_type = 'Lock'
        AND datname = '$DB_NAME';
    ")

    echo "  Blocked queries: $BLOCKED"

    if [ "$BLOCKED" -gt 5 ]; then
        log_crit "$BLOCKED queries waiting on locks"
    elif [ "$BLOCKED" -gt 0 ]; then
        log_warn "$BLOCKED queries waiting on locks"
    else
        log_ok "No lock waits"
    fi
}

check_replication() {
    header "Replication Status"

    REPLICA_COUNT=$(run_query "SELECT count(*) FROM pg_stat_replication;")

    if [ "$REPLICA_COUNT" -eq 0 ]; then
        echo "  No replicas configured"
        log_ok "Standalone instance (no replication)"
    else
        echo "  Active replicas: $REPLICA_COUNT"

        LAG=$(run_query "
            SELECT max(EXTRACT(EPOCH FROM now() - write_lag))
            FROM pg_stat_replication;
        ")

        if [ -n "$LAG" ] && [ "${LAG%.*}" -gt 60 ]; then
            log_warn "Replication lag: ${LAG}s"
        else
            log_ok "Replication healthy"
        fi
    fi
}

do_vacuum() {
    header "Running VACUUM ANALYZE"

    echo "  This may take a while on large databases..."

    if [[ "$OSTYPE" == "darwin"* ]]; then
        psql -U "$DB_USER" -d "$DB_NAME" -c "VACUUM ANALYZE;" 2>/dev/null
    else
        sudo -u "$DB_USER" psql -d "$DB_NAME" -c "VACUUM ANALYZE;" 2>/dev/null
    fi

    log_ok "VACUUM ANALYZE complete"
}

print_summary() {
    header "Health Check Summary"

    echo ""
    if [ $EXIT_CODE -eq 0 ]; then
        echo -e "${GREEN}✅ Database is HEALTHY${NC}"
    elif [ $EXIT_CODE -eq 1 ]; then
        echo -e "${YELLOW}⚠️  Database has WARNINGS${NC}"
        for w in "${WARNINGS[@]}"; do
            echo "   - $w"
        done
    else
        echo -e "${RED}🔴 Database has CRITICAL issues${NC}"
        for c in "${CRITICALS[@]}"; do
            echo "   - $c"
        done
        if [ ${#WARNINGS[@]} -gt 0 ]; then
            echo ""
            echo "  Also with warnings:"
            for w in "${WARNINGS[@]}"; do
                echo "   - $w"
            done
        fi
    fi

    echo ""
    echo "  Timestamp: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo "  Database:  $DB_NAME"
    echo ""
}

# Help
if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    echo "OCTO PostgreSQL Health Check"
    echo ""
    echo "Usage: octo pg-health [database_name] [options]"
    echo ""
    echo "Options:"
    echo "  --vacuum     Run VACUUM ANALYZE after health check"
    echo "  --full       Run full maintenance (vacuum + reindex)"
    echo "  -h, --help   Show this help"
    echo ""
    echo "Environment variables:"
    echo "  PGUSER       PostgreSQL user (default: postgres)"
    echo ""
    echo "Exit codes:"
    echo "  0 = Healthy"
    echo "  1 = Warning"
    echo "  2 = Critical"
    exit 0
fi

# Check for options
DO_VACUUM=false
DO_FULL=false

for arg in "$@"; do
    case $arg in
        --vacuum) DO_VACUUM=true ;;
        --full) DO_FULL=true; DO_VACUUM=true ;;
    esac
done

# Main
main() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║          OCTO PostgreSQL Health Check                         ║"
    echo "╚════════════════════════════════════════════════════════════════╝"

    check_postgres_running
    check_connections
    check_cache
    check_vacuum
    check_xid
    check_long_queries
    check_disk
    check_locks
    check_replication

    if [ "$DO_VACUUM" = true ]; then
        do_vacuum
    fi

    print_summary

    exit $EXIT_CODE
}

main
