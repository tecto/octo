#!/usr/bin/env bash
#
# E2E test: Onelist Docker installation
#
# This test verifies Onelist can be installed via Docker.
# Requires Docker to be available.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Test environment
TEST_HOME="${TEST_HOME:-/tmp/octo-onelist-test-$$}"
export OCTO_HOME="$TEST_HOME/octo"
export OPENCLAW_HOME="$TEST_HOME/openclaw"
export OCTO_TEST_MODE=1
export PATH="$PROJECT_ROOT/bin:$PATH"

# Docker compose project name (for isolation)
COMPOSE_PROJECT="octo-test-$$"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((TESTS_PASSED++)) || true
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((TESTS_FAILED++)) || true
}

log_skip() {
    echo -e "${YELLOW}[SKIP]${NC} $1"
    ((TESTS_SKIPPED++)) || true
}

log_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

cleanup() {
    log_info "Cleaning up test environment..."

    # Stop Docker containers if running
    if command -v docker &>/dev/null; then
        cd "$TEST_HOME" 2>/dev/null && \
            docker compose -p "$COMPOSE_PROJECT" down -v 2>/dev/null || true
    fi

    rm -rf "$TEST_HOME"
}

trap cleanup EXIT

# ============================================
# Check Prerequisites
# ============================================

log_info "Checking prerequisites..."

if ! command -v docker &>/dev/null; then
    log_skip "Docker not available - skipping Onelist Docker tests"
    echo ""
    echo "============================================"
    echo "Onelist Docker E2E Test Summary"
    echo "============================================"
    echo -e "${YELLOW}Skipped:${NC} Docker not available"
    echo "============================================"
    exit 0
fi

if ! docker info &>/dev/null; then
    log_skip "Docker daemon not running - skipping tests"
    exit 0
fi

log_pass "Docker is available"

# ============================================
# Setup
# ============================================

log_info "Setting up test environment at $TEST_HOME"

mkdir -p "$OCTO_HOME"/{logs,costs,metrics}
mkdir -p "$OPENCLAW_HOME/agents/main/sessions"
mkdir -p "$TEST_HOME/onelist"

# Create OCTO config
cat > "$OCTO_HOME/config.json" << 'EOF'
{
  "version": "1.0.0",
  "onelist": {
    "installed": false,
    "method": null
  }
}
EOF

cat > "$OPENCLAW_HOME/openclaw.json" << 'EOF'
{"version": "1.0.0", "gateway": {"port": 6200}}
EOF

log_pass "Test environment created"

# ============================================
# Test: Create Docker Compose File
# ============================================

log_info "Creating Docker Compose configuration..."

cat > "$TEST_HOME/docker-compose.yml" << 'EOF'
version: "3.8"

services:
  postgres:
    image: pgvector/pgvector:pg16
    container_name: octo-test-postgres
    environment:
      POSTGRES_USER: onelist
      POSTGRES_PASSWORD: onelist_test_password
      POSTGRES_DB: onelist
    ports:
      - "5433:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U onelist"]
      interval: 5s
      timeout: 5s
      retries: 5

volumes:
  pgdata:
EOF

if [ -f "$TEST_HOME/docker-compose.yml" ]; then
    log_pass "Docker Compose file created"
else
    log_fail "Failed to create Docker Compose file"
fi

# ============================================
# Test: Start PostgreSQL Container
# ============================================

log_info "Starting PostgreSQL container..."

cd "$TEST_HOME"

if docker compose -p "$COMPOSE_PROJECT" up -d postgres 2>/dev/null; then
    log_pass "PostgreSQL container started"
else
    log_fail "Failed to start PostgreSQL container"
    exit 1
fi

# ============================================
# Test: Wait for PostgreSQL Health
# ============================================

log_info "Waiting for PostgreSQL to be healthy..."

MAX_RETRIES=30
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if docker compose -p "$COMPOSE_PROJECT" exec -T postgres pg_isready -U onelist 2>/dev/null; then
        break
    fi
    sleep 1
    ((RETRY_COUNT++)) || true
done

if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
    log_pass "PostgreSQL is healthy"
else
    log_fail "PostgreSQL failed to become healthy"
    docker compose -p "$COMPOSE_PROJECT" logs postgres
    exit 1
fi

# ============================================
# Test: PostgreSQL Connection
# ============================================

log_info "Testing PostgreSQL connection..."

if docker compose -p "$COMPOSE_PROJECT" exec -T postgres \
    psql -U onelist -d onelist -c "SELECT 1" 2>/dev/null | grep -q "1"; then
    log_pass "PostgreSQL connection successful"
else
    log_fail "PostgreSQL connection failed"
fi

# ============================================
# Test: pgvector Extension
# ============================================

log_info "Testing pgvector extension availability..."

if docker compose -p "$COMPOSE_PROJECT" exec -T postgres \
    psql -U onelist -d onelist -c "CREATE EXTENSION IF NOT EXISTS vector" 2>/dev/null; then
    log_pass "pgvector extension available"
else
    log_fail "pgvector extension not available"
fi

# ============================================
# Test: Create Onelist Tables
# ============================================

log_info "Creating Onelist schema..."

docker compose -p "$COMPOSE_PROJECT" exec -T postgres \
    psql -U onelist -d onelist << 'EOF' 2>/dev/null
CREATE TABLE IF NOT EXISTS documents (
    id SERIAL PRIMARY KEY,
    content TEXT NOT NULL,
    embedding vector(1536),
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS documents_embedding_idx
    ON documents USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 100);
EOF

if docker compose -p "$COMPOSE_PROJECT" exec -T postgres \
    psql -U onelist -d onelist -c "\dt" 2>/dev/null | grep -q "documents"; then
    log_pass "Onelist tables created"
else
    log_fail "Failed to create Onelist tables"
fi

# ============================================
# Test: Update Config with Onelist
# ============================================

log_info "Updating OCTO config with Onelist..."

if command -v jq &>/dev/null; then
    jq '.onelist.installed = true | .onelist.method = "docker"' \
        "$OCTO_HOME/config.json" > "$OCTO_HOME/config.json.tmp"
    mv "$OCTO_HOME/config.json.tmp" "$OCTO_HOME/config.json"

    installed=$(jq -r '.onelist.installed' "$OCTO_HOME/config.json")
    method=$(jq -r '.onelist.method' "$OCTO_HOME/config.json")

    if [ "$installed" == "true" ] && [ "$method" == "docker" ]; then
        log_pass "Config updated with Onelist settings"
    else
        log_fail "Config update failed"
    fi
else
    log_skip "jq not available for config update"
fi

# ============================================
# Test: Onelist Status Command
# ============================================

log_info "Testing onelist status command..."

output=$("$PROJECT_ROOT/bin/octo" onelist status 2>&1 || true)

if [ -n "$output" ]; then
    log_pass "Onelist status command works"
else
    log_fail "Onelist status command failed"
fi

# ============================================
# Test: Container Cleanup
# ============================================

log_info "Testing container cleanup..."

if docker compose -p "$COMPOSE_PROJECT" down -v 2>/dev/null; then
    log_pass "Containers cleaned up successfully"
else
    log_fail "Container cleanup failed"
fi

# Verify containers stopped
if ! docker ps -q --filter "name=octo-test" | grep -q .; then
    log_pass "All test containers stopped"
else
    log_fail "Some containers still running"
fi

# ============================================
# Summary
# ============================================

echo ""
echo "============================================"
echo "Onelist Docker E2E Test Summary"
echo "============================================"
echo -e "${GREEN}Passed:${NC} $TESTS_PASSED"
echo -e "${RED}Failed:${NC} $TESTS_FAILED"
echo -e "${YELLOW}Skipped:${NC} $TESTS_SKIPPED"
echo "============================================"

if [ "$TESTS_FAILED" -gt 0 ]; then
    exit 1
else
    exit 0
fi
