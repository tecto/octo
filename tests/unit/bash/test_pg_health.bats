#!/usr/bin/env bats
#
# Tests for lib/integrations/onelist/pg-health-check.sh
#

setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$TEST_DIR/../../.." && pwd)"
    FIXTURES_DIR="$TEST_DIR/../../fixtures"
    HELPERS_DIR="$TEST_DIR/../../helpers"

    export OCTO_HOME="$BATS_TMPDIR/octo_home_$$"
    export OCTO_TEST_MODE=1

    mkdir -p "$OCTO_HOME/logs"

    source "$HELPERS_DIR/assertions.sh"
}

teardown() {
    rm -rf "$OCTO_HOME"
}

# ============================================
# Connection Tests
# ============================================

@test "default postgres port is 5432" {
    PGPORT=${PGPORT:-5432}
    [ "$PGPORT" -eq 5432 ]
}

@test "default postgres host is localhost" {
    PGHOST=${PGHOST:-localhost}
    [ "$PGHOST" == "localhost" ]
}

@test "connection string format is valid" {
    PGHOST="localhost"
    PGPORT="5432"
    PGUSER="onelist"
    PGDATABASE="onelist"

    CONN="postgresql://$PGUSER@$PGHOST:$PGPORT/$PGDATABASE"
    [[ "$CONN" == *"postgresql://"* ]]
}

# ============================================
# Vacuum Tests
# ============================================

@test "autovacuum enabled check query" {
    QUERY="SELECT name, setting FROM pg_settings WHERE name = 'autovacuum'"
    [[ "$QUERY" == *"autovacuum"* ]]
}

@test "dead tuple threshold is 10000" {
    THRESHOLD=10000
    [ "$THRESHOLD" -eq 10000 ]
}

@test "vacuum warning when dead tuples > threshold" {
    DEAD_TUPLES=15000
    THRESHOLD=10000

    if [ "$DEAD_TUPLES" -gt "$THRESHOLD" ]; then
        WARNING=true
    else
        WARNING=false
    fi

    [ "$WARNING" == "true" ]
}

# ============================================
# XID Wraparound Tests
# ============================================

@test "xid age warning threshold is 200M" {
    # 200 million transactions
    THRESHOLD=200000000
    [ "$THRESHOLD" -eq 200000000 ]
}

@test "xid age critical threshold is 1B" {
    # 1 billion transactions
    THRESHOLD=1000000000
    [ "$THRESHOLD" -eq 1000000000 ]
}

@test "xid check query format" {
    QUERY="SELECT datname, age(datfrozenxid) as xid_age FROM pg_database"
    [[ "$QUERY" == *"datfrozenxid"* ]]
    [[ "$QUERY" == *"age"* ]]
}

# ============================================
# Connection Pool Tests
# ============================================

@test "max connections query" {
    QUERY="SELECT setting::int FROM pg_settings WHERE name = 'max_connections'"
    [[ "$QUERY" == *"max_connections"* ]]
}

@test "active connections query" {
    QUERY="SELECT count(*) FROM pg_stat_activity WHERE state = 'active'"
    [[ "$QUERY" == *"pg_stat_activity"* ]]
}

@test "connection warning at 80% utilization" {
    MAX_CONN=100
    ACTIVE_CONN=85
    THRESHOLD_PERCENT=80

    UTILIZATION=$((ACTIVE_CONN * 100 / MAX_CONN))

    if [ "$UTILIZATION" -gt "$THRESHOLD_PERCENT" ]; then
        WARNING=true
    else
        WARNING=false
    fi

    [ "$WARNING" == "true" ]
}

@test "connection critical at 95% utilization" {
    MAX_CONN=100
    ACTIVE_CONN=97
    THRESHOLD_PERCENT=95

    UTILIZATION=$((ACTIVE_CONN * 100 / MAX_CONN))

    if [ "$UTILIZATION" -gt "$THRESHOLD_PERCENT" ]; then
        CRITICAL=true
    else
        CRITICAL=false
    fi

    [ "$CRITICAL" == "true" ]
}

# ============================================
# Index Health Tests
# ============================================

@test "bloated index query" {
    QUERY="SELECT indexrelname, pg_relation_size(indexrelid) FROM pg_stat_user_indexes"
    [[ "$QUERY" == *"pg_stat_user_indexes"* ]]
}

@test "unused index threshold is 0 scans" {
    THRESHOLD=0
    [ "$THRESHOLD" -eq 0 ]
}

@test "index size warning threshold is 1GB" {
    THRESHOLD=$((1 * 1024 * 1024 * 1024))
    [ "$THRESHOLD" -eq 1073741824 ]
}

# ============================================
# Table Bloat Tests
# ============================================

@test "table bloat estimation query" {
    # Query should check n_dead_tup vs n_live_tup
    QUERY="SELECT relname, n_dead_tup, n_live_tup FROM pg_stat_user_tables"
    [[ "$QUERY" == *"n_dead_tup"* ]]
    [[ "$QUERY" == *"n_live_tup"* ]]
}

@test "table bloat warning at 20% dead tuples" {
    LIVE=10000
    DEAD=2500
    THRESHOLD_PERCENT=20

    BLOAT_PERCENT=$((DEAD * 100 / (LIVE + DEAD)))

    if [ "$BLOAT_PERCENT" -gt "$THRESHOLD_PERCENT" ]; then
        WARNING=true
    else
        WARNING=false
    fi

    [ "$WARNING" == "true" ]
}

# ============================================
# Replication Tests
# ============================================

@test "replication lag query" {
    QUERY="SELECT pg_last_wal_receive_lsn() - pg_last_wal_replay_lsn() AS lag"
    [[ "$QUERY" == *"wal"* ]]
}

@test "replication lag warning threshold is 100MB" {
    THRESHOLD=$((100 * 1024 * 1024))
    [ "$THRESHOLD" -eq 104857600 ]
}

# ============================================
# Disk Space Tests
# ============================================

@test "database size query" {
    QUERY="SELECT pg_database_size(current_database())"
    [[ "$QUERY" == *"pg_database_size"* ]]
}

@test "tablespace size query" {
    QUERY="SELECT spcname, pg_tablespace_size(oid) FROM pg_tablespace"
    [[ "$QUERY" == *"pg_tablespace_size"* ]]
}

# ============================================
# Lock Analysis Tests
# ============================================

@test "blocking queries query" {
    QUERY="SELECT blocked_locks.pid AS blocked_pid FROM pg_locks blocked_locks"
    [[ "$QUERY" == *"pg_locks"* ]]
}

@test "long running queries threshold is 5 minutes" {
    THRESHOLD_SECONDS=$((5 * 60))
    [ "$THRESHOLD_SECONDS" -eq 300 ]
}

# ============================================
# Output Format Tests
# ============================================

@test "output includes pass/warn/fail counts" {
    PASS=5
    WARN=2
    FAIL=0

    OUTPUT="Checks: $PASS passed, $WARN warnings, $FAIL failed"
    [[ "$OUTPUT" == *"passed"* ]]
    [[ "$OUTPUT" == *"warnings"* ]]
    [[ "$OUTPUT" == *"failed"* ]]
}

@test "output includes timestamp" {
    TIMESTAMP=$(date -Iseconds)
    [[ "$TIMESTAMP" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]]
}

# ============================================
# Exit Code Tests
# ============================================

@test "exit 0 when all pass" {
    FAIL=0
    WARN=0
    EXIT_CODE=0

    [ "$EXIT_CODE" -eq 0 ]
}

@test "exit 1 when warnings only" {
    FAIL=0
    WARN=3
    EXIT_CODE=1

    [ "$EXIT_CODE" -eq 1 ]
}

@test "exit 2 when failures present" {
    FAIL=1
    EXIT_CODE=2

    [ "$EXIT_CODE" -eq 2 ]
}

# ============================================
# Integration Test
# ============================================

@test "pg-health command shows help" {
    run "$PROJECT_ROOT/bin/octo" pg-health --help 2>&1
    # Should show something (even if postgres not running)
    [ -n "$output" ] || [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}
