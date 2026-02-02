# OCTO - OpenClaw Token Optimizer

**Reduce your OpenClaw API costs by 60-95%**

OCTO (OpenClaw Token Optimizer) is an open-source toolkit that helps OpenClaw users dramatically reduce their Anthropic API costs through intelligent optimization, monitoring, and optional local inference.

## Quick Start

```bash
# One-line install
curl -fsSL https://raw.githubusercontent.com/trinsiklabs/openclaw-token-optimizer/main/install.sh | bash

# Run the setup wizard
octo install

# Check your optimization status
octo status
```

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
| `octo status` | Show optimization status, savings, and health |
| `octo analyze` | Deep analysis of token usage patterns |
| `octo doctor` | Health check and diagnostics |
| `octo sentinel` | Manage bloat detection service |
| `octo watchdog` | Manage health monitoring service |
| `octo surgery` | Manual recovery from bloated sessions |
| `octo onelist` | Install Onelist local inference |
| `octo pg-health` | PostgreSQL maintenance (with Onelist) |

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

- GitHub Issues: [trinsiklabs/openclaw-token-optimizer](https://github.com/trinsiklabs/openclaw-token-optimizer/issues)
- Documentation: [docs.trinsiklabs.com/octo](https://docs.trinsiklabs.com/octo)

---

Built with care by [Trinsik Labs](https://trinsiklabs.com) for the OpenClaw community.
