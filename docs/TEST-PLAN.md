# OCTO Test Plan

## Overview

Comprehensive test suite for OCTO (OpenClaw Token Optimizer). Tests organized by component with unit, integration, and end-to-end coverage.

**Test Framework Strategy:**
- **Bash scripts**: [bats-core](https://github.com/bats-core/bats-core) (Bash Automated Testing System)
- **Python modules**: pytest with pytest-mock
- **TypeScript plugin**: Jest with ts-jest
- **Integration tests**: Docker-based test environment

---

## Directory Structure

```
tests/
├── unit/
│   ├── bash/
│   │   ├── test_octo_cli.bats
│   │   ├── test_install.bats
│   │   ├── test_status.bats
│   │   ├── test_analyze.bats
│   │   ├── test_doctor.bats
│   │   ├── test_onelist.bats
│   │   ├── test_bloat_sentinel.bats
│   │   ├── test_watchdog.bats
│   │   ├── test_surgery.bats
│   │   └── test_pg_health.bats
│   ├── python/
│   │   ├── test_cost_estimator.py
│   │   ├── test_model_tier.py
│   │   └── test_session_monitor.py
│   └── typescript/
│       └── test_plugin.ts
├── integration/
│   ├── test_install_flow.bats
│   ├── test_sentinel_intervention.bats
│   ├── test_cost_tracking_flow.py
│   └── test_onelist_integration.bats
├── e2e/
│   ├── test_full_install.sh
│   ├── test_bloat_recovery.sh
│   └── test_onelist_docker.sh
├── fixtures/
│   ├── sessions/
│   │   ├── healthy_session.jsonl
│   │   ├── bloated_session.jsonl
│   │   ├── injection_loop_session.jsonl
│   │   └── large_session.jsonl
│   ├── configs/
│   │   ├── default_config.json
│   │   ├── all_enabled.json
│   │   └── all_disabled.json
│   └── costs/
│       └── sample_costs.jsonl
├── mocks/
│   ├── mock_openclaw_home/
│   ├── mock_gateway_process.sh
│   └── mock_onelist_api.py
└── helpers/
    ├── setup_test_env.sh
    ├── teardown_test_env.sh
    └── assertions.sh
```

---

## 1. CLI Router Tests (`bin/octo`)

### Unit Tests (`test_octo_cli.bats`)

```bash
# Command routing
@test "routes 'install' to install.sh"
@test "routes 'status' to status.sh"
@test "routes 'analyze' to analyze.sh"
@test "routes 'doctor' to doctor.sh"
@test "routes 'sentinel' to bloat-sentinel.sh"
@test "routes 'watchdog' to openclaw-watchdog.sh"
@test "routes 'surgery' to bump-openclaw-bot.sh"
@test "routes 'onelist' to onelist.sh"
@test "routes 'pg-health' to pg-health-check.sh"

# Help and version
@test "shows help with -h flag"
@test "shows help with --help flag"
@test "shows help with 'help' command"
@test "shows help when no command given"
@test "shows version with -v flag"
@test "shows version with --version flag"

# Error handling
@test "exits with error for unknown command"
@test "error message includes 'octo --help' hint"
@test "exits with error when OPENCLAW_HOME missing"

# Environment setup
@test "creates OCTO_HOME directories on startup"
@test "uses default OCTO_HOME when not set"
@test "uses custom OCTO_HOME when set"
@test "uses default OCTO_PORT 6286 when not set"

# Banner display
@test "shows ASCII banner for help"
@test "banner includes 'OpenClaw Token Optimizer'"
```

---

## 2. Install Wizard Tests (`lib/cli/install.sh`)

### Unit Tests (`test_install.bats`)

```bash
# OpenClaw detection
@test "detects OpenClaw at default location"
@test "detects OpenClaw at custom OPENCLAW_HOME"
@test "exits with error when OpenClaw not found"
@test "counts existing session files"
@test "detects existing openclaw.json"

# Port availability
@test "check_port_available returns 0 for free port"
@test "check_port_available returns 1 for used port"
@test "falls back to ss when lsof unavailable"
@test "falls back to netstat when ss unavailable"

# Resource detection
@test "detects RAM on macOS (sysctl)"
@test "detects RAM on Linux (/proc/meminfo)"
@test "detects CPU cores on macOS"
@test "detects CPU cores on Linux"
@test "detects available disk space"

# Configuration generation
@test "generates valid JSON config"
@test "config includes version field"
@test "config includes installedAt timestamp"
@test "respects user feature selections"
@test "saves config to OCTO_HOME/config.json"

# Feature toggles
@test "defaults ENABLE_CACHING to true"
@test "prompt_yn handles Y default correctly"
@test "prompt_yn handles N default correctly"
@test "prompt_yn accepts lowercase y/n"

# Savings calculation
@test "calculates 25-40% for caching alone"
@test "calculates 35-50% additional for tiering"
@test "caps savings at 75% max"

# Onelist upsell
@test "shows Onelist prompt when resources sufficient"
@test "skips Onelist prompt when RAM < 4GB"
@test "skips Onelist prompt when CPU < 2 cores"
@test "skips Onelist prompt when disk < 10GB"

# Plugin installation
@test "creates plugin directory"
@test "copies plugin files when source exists"
@test "warns when plugin source not found"

# Reconfiguration
@test "detects existing config"
@test "prompts for reconfiguration"
@test "exits cleanly when user declines reconfigure"
```

---

## 3. Status Command Tests (`lib/cli/status.sh`)

### Unit Tests (`test_status.bats`)

```bash
# Config loading
@test "exits with message when config not found"
@test "loads config from OCTO_HOME/config.json"
@test "parses optimization.promptCaching.enabled"
@test "parses onelist.installed"

# Boolean formatting
@test "bool_to_status formats true as 'enabled'"
@test "bool_to_status formats false as 'disabled'"

# Service detection
@test "detects running bloat sentinel"
@test "detects stale sentinel PID"
@test "detects sentinel not running"
@test "detects running gateway"
@test "detects gateway not running"
@test "detects dashboard on configured port"

# Session analysis
@test "counts active sessions"
@test "excludes sessions.json from count"
@test "excludes .archived.* files from count"
@test "calculates total session size"
@test "identifies largest session"
@test "warns when largest session > 5MB"

# Cost summary
@test "reads today's cost file"
@test "calculates total cost"
@test "counts total requests"
@test "shows 'no data' when cost file missing"

# Intervention history
@test "lists recent intervention logs"
@test "shows 'none' when no interventions"
@test "parses timestamp from filename"
```

---

## 4. Analyze Command Tests (`lib/cli/analyze.sh`)

### Unit Tests (`test_analyze.bats`)

```bash
# Argument parsing
@test "parses --period=today"
@test "parses --period=yesterday"
@test "parses --period=week"
@test "parses --period=month"
@test "parses --session=<id>"
@test "parses -v/--verbose flag"
@test "shows help with -h flag"
@test "rejects unknown period"

# Session analysis
@test "calculates session file size"
@test "counts user messages"
@test "counts assistant messages"
@test "counts injection markers"
@test "warns on high injection count (>10)"
@test "estimates tokens as size/4"
@test "calculates cost estimate"

# Aggregate analysis
@test "discovers all session files"
@test "excludes archived sessions"
@test "detects bloated sessions (>10MB)"
@test "calculates average session size"

# Cost analysis
@test "finds today's cost file"
@test "finds yesterday's cost file"
@test "finds week's cost files"
@test "aggregates costs from JSONL"
@test "calculates cache efficiency"
@test "warns on low cache utilization (<20%)"

# Savings estimation
@test "reads feature states from config"
@test "stacks savings percentages"
@test "caps at 95% maximum"
@test "suggests Onelist when not installed"
```

---

## 5. Doctor Command Tests (`lib/cli/doctor.sh`)

### Unit Tests (`test_doctor.bats`)

```bash
# Check counters
@test "increments CHECKS_PASSED on pass"
@test "increments CHECKS_WARNED on warning"
@test "increments CHECKS_FAILED on failure"

# Configuration checks
@test "passes when config exists"
@test "fails when config missing"
@test "passes when config is valid JSON"
@test "fails when config is invalid JSON"
@test "passes when OpenClaw dir exists"
@test "fails when OpenClaw dir missing"

# Dependency checks
@test "passes when python3 available"
@test "fails when python3 missing"
@test "passes when jq available"
@test "warns when jq missing"
@test "passes when curl available"
@test "warns when curl missing"

# Gateway health
@test "passes when gateway running"
@test "info when gateway not running"
@test "warns when memory > 300MB"
@test "critical when memory > 500MB"
@test "warns when uptime > 24h"

# Session health
@test "passes when no bloated sessions"
@test "fails when sessions > 10MB"
@test "passes when injection counts normal"
@test "warns when injection count > 10"

# Sentinel status
@test "passes when sentinel running"
@test "warns when sentinel PID stale"
@test "warns when sentinel enabled but not running"
@test "info when sentinel disabled"

# Log analysis
@test "passes when no rate limit errors"
@test "warns when rate limit errors > 2"
@test "critical when rate limit errors > 10"
@test "critical when overflow errors found"

# Disk space
@test "passes when disk < 80%"
@test "warns when disk > 80%"
@test "critical when disk > 90%"

# Exit codes
@test "exits 0 when all pass"
@test "exits 1 when warnings only"
@test "exits 2 when failures present"
```

---

## 6. Bloat Sentinel Tests (`lib/watchdog/bloat-sentinel.sh`)

### Unit Tests (`test_bloat_sentinel.bats`)

```bash
# Injection block counting
@test "counts zero blocks in clean message"
@test "counts single injection block"
@test "counts multiple injection blocks"
@test "ignores partial marker text"
@test "requires 'Recovered Conversation Context' after marker"

# Layer 1: Nested blocks
@test "triggers when >1 block in single message"
@test "does not trigger for exactly 1 block"
@test "does not trigger for 0 blocks"

# Layer 2: Rapid growth
@test "tracks size history per session"
@test "calculates growth rate in KB/min"
@test "triggers when growth > 1MB in 60s with markers"
@test "does not trigger growth without markers"
@test "prunes history older than 60s"

# Layer 3: Size with markers
@test "triggers when size > 10MB with >= 2 markers"
@test "does not trigger for large size without markers"
@test "does not trigger for small size with markers"

# Layer 4: Total markers (monitor only)
@test "logs when total markers > 10"
@test "does not intervene for layer 4"

# Intervention
@test "creates intervention log"
@test "archives session to dated directory"
@test "preserves original session as backup"
@test "resets session file"
@test "restarts gateway"

# Daemon management
@test "creates PID file on daemon start"
@test "removes PID file on stop"
@test "detects stale PID"
@test "prevents duplicate daemon"

# Status display
@test "shows running status with PID"
@test "shows dead status for stale PID"
@test "shows not running when no PID file"
@test "lists recent interventions"
@test "shows session health summary"
```

### Fixtures Needed

```jsonl
# fixtures/sessions/healthy_session.jsonl
{"type":"message","message":{"role":"user","content":"Hello"}}
{"type":"message","message":{"role":"assistant","content":"Hi there"}}

# fixtures/sessions/injection_loop_session.jsonl
{"type":"message","message":{"role":"user","content":"[INJECTION-DEPTH:1] Recovered Conversation Context..."}}
{"type":"message","message":{"role":"user","content":"[INJECTION-DEPTH:2] Recovered Conversation Context... [INJECTION-DEPTH:1] Recovered Conversation Context..."}}
```

---

## 7. Python Module Tests

### Cost Estimator (`test_cost_estimator.py`)

```python
class TestCost:
    def test_auto_calculates_total(self):
    def test_explicit_total_overrides(self):

class TestCostEstimator:
    # Pricing
    def test_loads_pricing_from_file(self):
    def test_falls_back_to_defaults_when_file_missing(self):
    def test_resolves_model_aliases(self):

    # Calculation
    def test_calculates_input_cost(self):
    def test_calculates_output_cost(self):
    def test_calculates_cache_read_cost(self):
    def test_calculates_cache_write_cost(self):
    def test_subtracts_cached_from_input(self):
    def test_handles_zero_tokens(self):
    def test_handles_missing_usage(self):

    # Recording
    def test_creates_costs_directory(self):
    def test_appends_to_daily_file(self):
    def test_includes_session_id(self):
    def test_generates_iso_timestamp(self):

    # Summary
    def test_returns_zeros_for_missing_file(self):
    def test_aggregates_daily_costs(self):
    def test_counts_requests(self):
    def test_skips_malformed_lines(self):

    # Savings estimation
    def test_estimates_savings_with_caching(self):
    def test_estimates_savings_with_tiering(self):
    def test_estimates_combined_savings(self):
    def test_handles_zero_base_cost(self):
```

### Model Tier (`test_model_tier.py`)

```python
class TestTierDecision:
    def test_dataclass_fields(self):

class TestModelTier:
    # Pattern matching
    def test_haiku_simple_questions(self):
    def test_haiku_file_operations(self):
    def test_haiku_confirmations(self):
    def test_haiku_tool_selection(self):

    def test_opus_architecture_design(self):
    def test_opus_tradeoff_analysis(self):
    def test_opus_security_review(self):

    def test_sonnet_code_generation(self):
    def test_sonnet_bug_fixes(self):
    def test_sonnet_refactoring(self):

    # Default behavior
    def test_defaults_to_sonnet(self):
    def test_default_has_lower_confidence(self):

    # Configuration
    def test_loads_custom_patterns(self):
    def test_uses_defaults_when_config_missing(self):

    # should_tier
    def test_respects_enabled_config(self):
    def test_preserves_opus_model(self):
    def test_allows_downgrade_to_haiku(self):
```

### Session Monitor (`test_session_monitor.py`)

```python
class TestSessionHealth:
    def test_dataclass_fields(self):

class TestSessionMonitor:
    # Analysis
    def test_calculates_file_size(self):
    def test_estimates_tokens(self):
    def test_counts_messages(self):
    def test_counts_injection_markers(self):
    def test_finds_max_nested_injections(self):
    def test_calculates_context_utilization(self):

    # Status determination
    def test_critical_for_nested_injections(self):
    def test_critical_for_size_over_10mb(self):
    def test_critical_for_high_injection_count(self):
    def test_critical_for_context_over_90_percent(self):
    def test_warning_for_size_over_2mb(self):
    def test_warning_for_moderate_injections(self):
    def test_warning_for_context_over_70_percent(self):
    def test_warning_for_rapid_growth(self):
    def test_healthy_for_normal_session(self):

    # Growth rate
    def test_calculates_growth_rate(self):
    def test_requires_two_data_points(self):
    def test_prunes_old_history(self):

    # Discovery
    def test_finds_all_sessions(self):
    def test_excludes_sessions_json(self):
    def test_excludes_archived_files(self):

    # Alerts
    def test_returns_warnings_and_criticals(self):
    def test_excludes_healthy_from_alerts(self):
```

---

## 8. TypeScript Plugin Tests (`test_plugin.ts`)

```typescript
describe('loadConfig', () => {
  it('loads config from file')
  it('returns defaults when file missing')
  it('handles malformed JSON')
})

describe('classifyMessage', () => {
  it('returns haiku for simple questions')
  it('returns opus for architecture tasks')
  it('returns sonnet for code generation')
  it('defaults to sonnet for unknown')
})

describe('onBeforeRequest', () => {
  it('applies model tiering when enabled')
  it('skips tiering when disabled')
  it('preserves opus model')
  it('adds cache headers when enabled')
  it('adds cache control to system prompt')
})

describe('onAfterResponse', () => {
  it('records cost when tracking enabled')
  it('skips recording when disabled')
  it('handles missing usage data')
})

describe('recordCost', () => {
  it('creates costs directory')
  it('appends to daily file')
  it('calculates correct costs')
  it('handles all model tiers')
})
```

---

## 9. Integration Tests

### Install Flow (`test_install_flow.bats`)

```bash
@test "full install creates all expected files"
@test "install with all features enabled"
@test "install with all features disabled"
@test "install detects and uses custom port"
@test "install starts sentinel daemon"
@test "reconfigure preserves existing data"
```

### Sentinel Intervention (`test_sentinel_intervention.bats`)

```bash
@test "sentinel detects and intervenes on bloat"
@test "sentinel creates intervention log"
@test "sentinel archives bloated session"
@test "sentinel restarts gateway"
@test "gateway resumes after intervention"
```

### Cost Tracking (`test_cost_tracking_flow.py`)

```python
def test_plugin_records_cost_on_request():
def test_status_shows_recorded_costs():
def test_analyze_aggregates_costs():
def test_cost_files_persist_across_restarts():
```

---

## 10. End-to-End Tests

### Full Install (`test_full_install.sh`)

```bash
# Fresh install on clean system
# Verify all components functional
# Verify dashboard accessible
# Verify sentinel running
# Cleanup
```

### Bloat Recovery (`test_bloat_recovery.sh`)

```bash
# Create mock bloated session
# Trigger sentinel detection
# Verify intervention
# Verify session archived
# Verify gateway recovered
# Verify notification created
```

### Onelist Docker (`test_onelist_docker.sh`)

```bash
# Install Onelist via Docker
# Verify containers running
# Verify PostgreSQL healthy
# Verify Onelist API responding
# Verify memory plugin configured
# Cleanup containers
```

---

## 11. Test Fixtures

### Session Files

| File | Purpose | Characteristics |
|------|---------|-----------------|
| `healthy_session.jsonl` | Baseline | 10 messages, no injections, 50KB |
| `bloated_session.jsonl` | Size test | 500 messages, 15MB |
| `injection_loop_session.jsonl` | Layer 1 test | Nested injection blocks |
| `high_markers_session.jsonl` | Layer 4 test | 15 injection markers |
| `rapid_growth_session.jsonl` | Layer 2 test | Timestamps showing fast growth |

### Config Files

| File | Purpose |
|------|---------|
| `default_config.json` | Standard configuration |
| `all_enabled.json` | All features enabled |
| `all_disabled.json` | All features disabled |
| `onelist_installed.json` | With Onelist enabled |

### Cost Files

| File | Purpose |
|------|---------|
| `sample_costs.jsonl` | Mix of models and costs |
| `high_cache_costs.jsonl` | High cache utilization |
| `low_cache_costs.jsonl` | Low cache utilization |

---

## 12. Mock Components

### Mock OpenClaw Home

```
mocks/mock_openclaw_home/
├── openclaw.json
├── agents/
│   └── main/
│       └── sessions/
│           └── test-session.jsonl
└── plugins/
```

### Mock Gateway Process

```bash
#!/bin/bash
# mocks/mock_gateway_process.sh
# Simulates openclaw-gateway for testing
echo "Mock gateway running on PID $$"
while true; do sleep 1; done
```

### Mock Onelist API

```python
# mocks/mock_onelist_api.py
from flask import Flask, jsonify
app = Flask(__name__)

@app.route('/health')
def health():
    return jsonify({"status": "ok"})

@app.route('/api/v1/search', methods=['POST'])
def search():
    return jsonify({"results": []})
```

---

## 13. CI/CD Integration

### GitHub Actions Workflow

```yaml
name: OCTO Tests
on: [push, pull_request]

jobs:
  unit-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install bats
        run: npm install -g bats
      - name: Install pytest
        run: pip install pytest pytest-mock
      - name: Run bash tests
        run: bats tests/unit/bash/
      - name: Run python tests
        run: pytest tests/unit/python/

  integration-tests:
    runs-on: ubuntu-latest
    needs: unit-tests
    steps:
      - uses: actions/checkout@v4
      - name: Setup test environment
        run: ./tests/helpers/setup_test_env.sh
      - name: Run integration tests
        run: bats tests/integration/

  e2e-tests:
    runs-on: ubuntu-latest
    needs: integration-tests
    services:
      postgres:
        image: pgvector/pgvector:pg16
        env:
          POSTGRES_PASSWORD: postgres
    steps:
      - uses: actions/checkout@v4
      - name: Run E2E tests
        run: ./tests/e2e/test_full_install.sh
```

---

## 14. Coverage Goals

| Component | Target Coverage |
|-----------|-----------------|
| bin/octo | 90% |
| lib/cli/*.sh | 80% |
| lib/core/*.py | 95% |
| lib/watchdog/*.sh | 85% |
| lib/plugins/ | 90% |
| lib/integrations/ | 75% |

---

## 15. Running Tests

```bash
# All tests
make test

# Unit tests only
make test-unit

# Bash tests
bats tests/unit/bash/

# Python tests
pytest tests/unit/python/ -v

# Integration tests
make test-integration

# E2E tests (requires Docker)
make test-e2e

# Coverage report
make coverage
```
