# OCTO - OpenClaw Token Optimizer

**Reduce your OpenClaw API costs by 60-95%**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![OpenClaw Compatible](https://img.shields.io/badge/OpenClaw-Compatible-blue.svg)](https://openclaw.ai)

---

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/trinsiklabs/octo/main/install.sh | bash
```

That's it. Run `octo status` to see your optimization status.

<details>
<summary><strong>VPS / Server Install (non-interactive)</strong></summary>

For automated VPS deployments where you can't interact with prompts:

```bash
curl -fsSL https://raw.githubusercontent.com/trinsiklabs/octo/main/install-vps.sh | bash
```

With custom OpenClaw path:
```bash
OPENCLAW_HOME=/path/to/openclaw curl -fsSL https://raw.githubusercontent.com/trinsiklabs/octo/main/install-vps.sh | bash
```

With Onelist for maximum savings (90-95%):
```bash
OCTO_INSTALL_ONELIST=true curl -fsSL https://raw.githubusercontent.com/trinsiklabs/octo/main/install-vps.sh | bash
```

</details>

---

## What is OCTO?

OCTO (OpenClaw Token Optimizer) is an open-source toolkit that helps OpenClaw users dramatically reduce their Anthropic API costs through intelligent optimization, monitoring, and optional local inference.

## What Does OCTO Do?

### Standalone Optimizations (No Additional Infrastructure)

| Feature | Savings | How It Works |
|---------|---------|--------------|
| **Prompt Caching** | 25-40% | Enables Anthropic's cache headers for repeated context |
| **Model Tiering** | 35-50% | Routes simple tasks to Haiku, complex ones to Sonnet/Opus |
| **Session Monitoring** | Prevents overruns | Alerts before context window overflow |
| **Bloat Detection** | Prevents runaway costs | Detects and stops injection feedback loops |

### With Onelist Integration (Local Inference)

| Feature | Additional Savings | How It Works |
|---------|-------------------|--------------|
| **Semantic Memory** | 50-70% | Local vector search replaces context stuffing |
| **Conversation Continuity** | 80-90% | Resume sessions without re-injecting history |
| **Combined Total** | **90-95%** | All optimizations working together |

## Commands

| Command | Description |
|---------|-------------|
| `octo install` | Interactive setup wizard |
| `octo uninstall` | Remove OCTO installation |
| `octo reinstall` | Clean reinstall (removes config) |
| `octo upgrade` | Upgrade while preserving config |
| `octo status` | Show optimization status, savings, and health |
| `octo analyze` | Deep analysis of token usage patterns |
| `octo doctor` | Health check and diagnostics |
| `octo sentinel` | Manage bloat detection service |
| `octo watchdog` | Manage health monitoring service |
| `octo surgery` | Manual recovery from bloated sessions |
| `octo onelist` | Connect to Onelist for additional savings |
| `octo pg-health` | PostgreSQL maintenance (with Onelist) |

---

## Usage Manual

### Installation

#### Fresh Install

```bash
octo install
```

The interactive wizard guides you through:
1. OpenClaw detection
2. Prompt caching configuration
3. Model tiering setup
4. Session monitoring options
5. Bloat detection settings
6. Dashboard port selection

#### Already Installed?

If OCTO is already installed, `octo install` will fail and suggest alternatives:

```bash
# Remove OCTO completely
octo uninstall

# Clean reinstall (loses config)
octo reinstall

# Upgrade (preserves config)
octo upgrade
```

---

### Uninstall

```bash
octo uninstall [options]
```

**Options:**
| Flag | Description |
|------|-------------|
| `--force`, `-f` | Skip confirmation prompt |
| `--purge` | Remove all data including cost history |

**Examples:**
```bash
# Interactive uninstall (preserves cost history)
octo uninstall

# Force uninstall without prompts
octo uninstall --force

# Remove everything including historical data
octo uninstall --purge
```

---

### Reinstall

```bash
octo reinstall [options]
```

Performs a clean reinstall: uninstalls existing installation, then runs fresh install.

**Options:**
| Flag | Description |
|------|-------------|
| `--force`, `-f` | Skip confirmation prompt |

**Warning:** This removes your custom configuration. Use `octo upgrade` to preserve settings.

---

### Upgrade

```bash
octo upgrade
```

Upgrades OCTO while preserving:
- All user configuration
- Optimization preferences
- Custom settings
- Cost history

Also:
- Backs up config to `config.json.backup`
- Updates plugin files
- Restarts services if running

---

### Status

```bash
octo status
```

Shows:
- Current optimization settings
- Estimated savings
- Service health (sentinel, watchdog)
- Onelist connection status
- Recent cost metrics

---

### Analyze

```bash
octo analyze [options]
```

Deep analysis of your token usage patterns:
- Session size distribution
- Cache hit rates
- Model tier utilization
- Potential optimization opportunities

---

### Doctor

```bash
octo doctor
```

Health check and diagnostics:
- OpenClaw configuration validation
- Plugin installation status
- Service health
- Resource availability
- Common issue detection

---

### Sentinel (Bloat Detection)

```bash
octo sentinel <command>
```

**Commands:**
| Command | Description |
|---------|-------------|
| `start` | Start bloat detection daemon |
| `stop` | Stop the daemon |
| `status` | Check if running |
| `logs` | View recent logs |

**What it detects:**
- Injection feedback loops
- Runaway context growth
- Duplicate content patterns
- Memory leak indicators

---

### Watchdog (Health Monitoring)

```bash
octo watchdog <command>
```

**Commands:**
| Command | Description |
|---------|-------------|
| `start` | Start health monitor daemon |
| `stop` | Stop the daemon |
| `status` | Check if running |

**Monitors:**
- Context window utilization
- API response times
- Error rates
- Resource usage

---

### Surgery (Session Recovery)

```bash
octo surgery [session-id]
```

Manual recovery from bloated sessions:
- Analyzes session state
- Identifies bloat sources
- Offers recovery options
- Can trim or reset sessions

---

### Onelist Integration

```bash
octo onelist [options]
```

Connect to Onelist for 50-70% additional savings on top of OCTO optimizations.

**Options:**
| Flag | Description |
|------|-------------|
| `--url=URL` | Onelist URL (default: http://localhost:4000) |
| `--port=PORT` | Onelist port (default: 4000) |
| `--status` | Show connection status and detection results |
| `--detect` | Run detection only (show what was found) |
| `--disconnect` | Remove Onelist connection |

**Multi-Layer Detection:**

OCTO uses multiple methods to detect Onelist installations:

| Layer | Method | What It Checks |
|-------|--------|----------------|
| 1 | Process | `beam.smp` / Elixir processes with "onelist" |
| 2 | Docker | Running containers named "onelist" or using `trinsiklabs/onelist` |
| 3 | Config | `~/.onelist/config.json`, `docker-compose.yml`, `/opt/onelist/` |
| 4 | Systemd | `onelist.service` status |

If Onelist is detected but not responding on the expected port, OCTO will:
- Show what was detected and where
- Prompt for the correct port
- Offer to continue without Onelist support
- Provide instructions to start Onelist manually

**Examples:**
```bash
# Auto-detect local Onelist (uses multi-layer detection)
octo onelist

# Show detection results without connecting
octo onelist --detect

# Connect to remote Onelist
octo onelist --url=http://192.168.1.100:4000

# Check connection status
octo onelist --status

# Disconnect
octo onelist --disconnect
```

**Note:** OCTO does not install Onelist. If Onelist is not detected, OCTO offers to run the [onelist-local](https://github.com/trinsiklabs/onelist-local) installer.

---

### PostgreSQL Health (with Onelist)

```bash
octo pg-health [options]
```

PostgreSQL maintenance for Onelist installations:
- Vacuum analysis
- Index health
- Connection pool status
- Query performance

---

## Configuration

Configuration is stored in `~/.octo/config.json`.

### Key Settings

```json
{
  "optimization": {
    "promptCaching": {
      "enabled": true,
      "cacheSystemPrompt": true,
      "cacheTools": true,
      "cacheHistoryOlderThan": 5
    },
    "modelTiering": {
      "enabled": true,
      "defaultModel": "sonnet"
    }
  },
  "monitoring": {
    "sessionMonitor": {
      "enabled": true,
      "warningThreshold": 0.70,
      "criticalThreshold": 0.90
    },
    "bloatSentinel": {
      "enabled": true,
      "autoIntervene": true
    }
  },
  "dashboard": {
    "enabled": true,
    "port": 6286,
    "host": "localhost"
  },
  "onelist": {
    "url": null,
    "connected": false
  }
}
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `OCTO_HOME` | `~/.octo` | OCTO data directory |
| `OPENCLAW_HOME` | `~/.openclaw` | OpenClaw installation |
| `OCTO_PORT` | `6286` | Dashboard port |
| `ONELIST_URL` | `http://localhost:4000` | Onelist URL |
| `ONELIST_PORT` | `4000` | Onelist port |

---

## Web Dashboard

After installation, access the monitoring dashboard at:

```
http://localhost:6286
```

(Port 6286 = "OCTO" in T9/phone keypad)

## Requirements

- OpenClaw installed and configured
- Bash 4.0+
- Python 3.8+ (for monitoring components)
- jq (for JSON processing)

### For Onelist Integration

- 4GB+ RAM
- 2+ CPU cores
- 10GB+ free disk space
- Docker (recommended) or PostgreSQL 14+

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        OpenClaw                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                   OCTO Plugin Layer                       │  │
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────────────┐  │  │
│  │  │   Model     │ │   Prompt    │ │     Cost            │  │  │
│  │  │   Tiering   │ │   Caching   │ │     Tracking        │  │  │
│  │  └─────────────┘ └─────────────┘ └─────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────┘  │
│                              │                                  │
│  ┌───────────────────────────┴───────────────────────────────┐  │
│  │                   Monitoring Layer                        │  │
│  │  ┌─────────────┐ ┌─────────────┐ ┌─────────────────────┐  │  │
│  │  │   Bloat     │ │   Session   │ │     Watchdog        │  │  │
│  │  │   Sentinel  │ │   Monitor   │ │     Service         │  │  │
│  │  └─────────────┘ └─────────────┘ └─────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
                    ┌─────────┴─────────┐
                    │   Onelist Local   │  (Optional)
                    │  ┌─────────────┐  │
                    │  │  Semantic   │  │
                    │  │   Memory    │  │
                    │  └─────────────┘  │
                    │  ┌─────────────┐  │
                    │  │ PostgreSQL  │  │
                    │  │ + pgvector  │  │
                    │  └─────────────┘  │
                    └───────────────────┘
```

## Documentation

- [Technical Deep Dive](./OCTO-TECHNICAL-REPORT.md) - Comprehensive technical documentation
- [Installation Guide](./docs/installation.md) - Detailed setup instructions
- [Configuration Reference](./docs/configuration.md) - All configuration options
- [Troubleshooting](./docs/troubleshooting.md) - Common issues and solutions

## License

MIT License - See [LICENSE](./LICENSE) for details.

## Contributing

Contributions welcome! Please read our [Contributing Guide](./CONTRIBUTING.md) before submitting PRs.

## Support

- GitHub Issues: [trinsiklabs/octo](https://github.com/trinsiklabs/octo/issues)
- Documentation: [docs.trinsiklabs.com/octo](https://docs.trinsiklabs.com/octo)

---

Built with care by [Trinsik Labs](https://trinsiklabs.com) for the OpenClaw community.
