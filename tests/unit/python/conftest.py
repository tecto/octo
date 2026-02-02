"""
Pytest configuration and fixtures for OCTO tests.
"""

import json
import os
import sys
import tempfile
from pathlib import Path

import pytest

# Add lib directories to path
PROJECT_ROOT = Path(__file__).parent.parent.parent.parent
sys.path.insert(0, str(PROJECT_ROOT / "lib" / "core"))

# Fixtures directory
FIXTURES_DIR = Path(__file__).parent.parent.parent / "fixtures"


@pytest.fixture
def temp_dir():
    """Create a temporary directory for tests."""
    with tempfile.TemporaryDirectory() as tmpdir:
        yield Path(tmpdir)


@pytest.fixture
def mock_openclaw_home(temp_dir):
    """Create a mock OpenClaw home directory."""
    openclaw_home = temp_dir / "openclaw"
    sessions_dir = openclaw_home / "agents" / "main" / "sessions"
    sessions_dir.mkdir(parents=True)

    # Create openclaw.json
    config = {
        "version": "1.0.0",
        "gateway": {"port": 6200}
    }
    (openclaw_home / "openclaw.json").write_text(json.dumps(config))

    return openclaw_home


@pytest.fixture
def mock_octo_home(temp_dir):
    """Create a mock OCTO home directory."""
    octo_home = temp_dir / "octo"
    octo_home.mkdir()

    # Create subdirectories
    (octo_home / "logs").mkdir()
    (octo_home / "costs").mkdir()
    (octo_home / "metrics").mkdir()
    (octo_home / "interventions").mkdir()

    return octo_home


@pytest.fixture
def sample_config(mock_octo_home):
    """Create a sample OCTO config."""
    config = {
        "version": "1.0.0",
        "installedAt": "2026-01-15T10:00:00Z",
        "optimization": {
            "promptCaching": {"enabled": True},
            "modelTiering": {"enabled": True}
        },
        "monitoring": {
            "sessionMonitoring": {"enabled": True},
            "bloatDetection": {"enabled": True}
        },
        "costTracking": {"enabled": True},
        "onelist": {"installed": False}
    }

    config_path = mock_octo_home / "config.json"
    config_path.write_text(json.dumps(config, indent=2))

    return config_path


@pytest.fixture
def sample_session(mock_openclaw_home):
    """Create a sample session file."""
    sessions_dir = mock_openclaw_home / "agents" / "main" / "sessions"
    session_file = sessions_dir / "test-session.jsonl"

    messages = [
        {"type": "message", "message": {"role": "user", "content": "Hello"}},
        {"type": "message", "message": {"role": "assistant", "content": "Hi there!"}},
        {"type": "message", "message": {"role": "user", "content": "How are you?"}},
        {"type": "message", "message": {"role": "assistant", "content": "I'm doing well, thanks!"}},
    ]

    with open(session_file, "w") as f:
        for msg in messages:
            f.write(json.dumps(msg) + "\n")

    return session_file


@pytest.fixture
def bloated_session(mock_openclaw_home):
    """Create a bloated session file with injection markers."""
    sessions_dir = mock_openclaw_home / "agents" / "main" / "sessions"
    session_file = sessions_dir / "bloated-session.jsonl"

    with open(session_file, "w") as f:
        # Normal messages
        for i in range(10):
            f.write(json.dumps({
                "type": "message",
                "message": {"role": "user", "content": f"Message {i}"}
            }) + "\n")

        # Injection markers
        for i in range(5):
            f.write(json.dumps({
                "type": "message",
                "message": {
                    "role": "user",
                    "content": f"[INJECTION-DEPTH:1] Recovered Conversation Context {i}"
                }
            }) + "\n")

        # Nested injection
        f.write(json.dumps({
            "type": "message",
            "message": {
                "role": "user",
                "content": "[INJECTION-DEPTH:2] Recovered Conversation Context [INJECTION-DEPTH:1] Recovered Conversation Context"
            }
        }) + "\n")

    return session_file


@pytest.fixture
def sample_costs(mock_octo_home):
    """Create sample cost data."""
    from datetime import datetime

    costs_dir = mock_octo_home / "costs"
    today = datetime.now().strftime("%Y-%m-%d")
    cost_file = costs_dir / f"costs-{today}.jsonl"

    costs = [
        {
            "timestamp": "2026-01-15T10:00:00Z",
            "session_id": "session-1",
            "model": "claude-sonnet-4-20250514",
            "input_tokens": 1000,
            "output_tokens": 500,
            "total_cost": 0.0105
        },
        {
            "timestamp": "2026-01-15T11:00:00Z",
            "session_id": "session-1",
            "model": "claude-haiku-3-5-20241022",
            "input_tokens": 500,
            "output_tokens": 200,
            "total_cost": 0.0015
        },
    ]

    with open(cost_file, "w") as f:
        for cost in costs:
            f.write(json.dumps(cost) + "\n")

    return cost_file


@pytest.fixture
def pricing_file(temp_dir):
    """Create a pricing configuration file."""
    pricing = {
        "models": {
            "claude-sonnet-4-20250514": {
                "input_per_mtok": 3.0,
                "output_per_mtok": 15.0,
                "cache_read_per_mtok": 0.30,
                "cache_write_per_mtok": 3.75
            },
            "claude-haiku-3-5-20241022": {
                "input_per_mtok": 1.0,
                "output_per_mtok": 5.0,
                "cache_read_per_mtok": 0.10,
                "cache_write_per_mtok": 1.25
            },
            "claude-opus-4-20250514": {
                "input_per_mtok": 15.0,
                "output_per_mtok": 75.0,
                "cache_read_per_mtok": 1.50,
                "cache_write_per_mtok": 18.75
            }
        },
        "aliases": {
            "sonnet": "claude-sonnet-4-20250514",
            "haiku": "claude-haiku-3-5-20241022",
            "opus": "claude-opus-4-20250514"
        }
    }

    pricing_path = temp_dir / "model_pricing.json"
    pricing_path.write_text(json.dumps(pricing, indent=2))

    return pricing_path
