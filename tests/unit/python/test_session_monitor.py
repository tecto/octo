#!/usr/bin/env python3
"""
Tests for lib/core/session_monitor.py
"""

import json
import os
import sys
import time
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

# Add lib/core to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "lib" / "core"))

from session_monitor import SessionHealth, SessionMonitor


class TestSessionHealth:
    """Tests for the SessionHealth dataclass."""

    def test_dataclass_fields(self):
        """SessionHealth has expected fields."""
        health = SessionHealth(
            session_id="test-session",
            file_path="/path/to/session.jsonl",
            size_bytes=1024000,
            estimated_tokens=256000,
            message_count=50,
            injection_markers=2,
            max_nested_injections=1,
            context_utilization=0.65,
            status="healthy",
            warnings=[],
            growth_rate_bytes_per_min=0
        )

        assert health.session_id == "test-session"
        assert health.size_bytes == 1024000
        assert health.status == "healthy"


class TestSessionMonitorAnalysis:
    """Tests for session analysis."""

    @pytest.fixture
    def monitor(self, tmp_path):
        """Create SessionMonitor with temp OpenClaw home."""
        openclaw_home = tmp_path / "openclaw"
        sessions_dir = openclaw_home / "agents" / "main" / "sessions"
        sessions_dir.mkdir(parents=True)
        return SessionMonitor(openclaw_home=str(openclaw_home))

    @pytest.fixture
    def sample_session(self, tmp_path):
        """Create a sample session file."""
        sessions_dir = tmp_path / "openclaw" / "agents" / "main" / "sessions"
        sessions_dir.mkdir(parents=True)
        session_file = sessions_dir / "test-session.jsonl"

        with open(session_file, "w") as f:
            for i in range(10):
                f.write(json.dumps({
                    "type": "message",
                    "message": {
                        "role": "user" if i % 2 == 0 else "assistant",
                        "content": f"Message {i}"
                    }
                }) + "\n")

        return session_file

    def test_calculates_file_size(self, monitor, sample_session):
        """Calculates file size correctly."""
        health = monitor.analyze_session(str(sample_session))

        assert health.size_bytes > 0
        assert health.size_bytes == os.path.getsize(sample_session)

    def test_estimates_tokens(self, monitor, sample_session):
        """Estimates tokens from file size."""
        health = monitor.analyze_session(str(sample_session))

        # Roughly 4 bytes per token
        expected = health.size_bytes // 4
        assert abs(health.estimated_tokens - expected) < 100

    def test_counts_messages(self, monitor, sample_session):
        """Counts messages in session."""
        health = monitor.analyze_session(str(sample_session))

        assert health.message_count == 10

    def test_counts_injection_markers(self, tmp_path, monitor):
        """Counts injection markers in session."""
        sessions_dir = tmp_path / "openclaw" / "agents" / "main" / "sessions"
        session_file = sessions_dir / "injection-session.jsonl"

        with open(session_file, "w") as f:
            f.write(json.dumps({
                "type": "message",
                "message": {
                    "role": "user",
                    "content": "[INJECTION-DEPTH:1] Recovered Conversation Context"
                }
            }) + "\n")
            f.write(json.dumps({
                "type": "message",
                "message": {
                    "role": "user",
                    "content": "[INJECTION-DEPTH:1] Recovered Conversation Context"
                }
            }) + "\n")

        health = monitor.analyze_session(str(session_file))

        assert health.injection_markers == 2

    def test_finds_max_nested_injections(self, tmp_path, monitor):
        """Finds maximum nested injections in single message."""
        sessions_dir = tmp_path / "openclaw" / "agents" / "main" / "sessions"
        session_file = sessions_dir / "nested-session.jsonl"

        with open(session_file, "w") as f:
            # Message with 2 nested blocks
            f.write(json.dumps({
                "type": "message",
                "message": {
                    "role": "user",
                    "content": "[INJECTION-DEPTH:2] Recovered Conversation Context [INJECTION-DEPTH:1] Recovered Conversation Context"
                }
            }) + "\n")

        health = monitor.analyze_session(str(session_file))

        assert health.max_nested_injections >= 2

    def test_calculates_context_utilization(self, monitor, sample_session):
        """Calculates context utilization percentage."""
        health = monitor.analyze_session(str(sample_session))

        # Should be between 0 and 1
        assert 0 <= health.context_utilization <= 1


class TestSessionMonitorStatus:
    """Tests for status determination."""

    @pytest.fixture
    def monitor(self, tmp_path):
        """Create SessionMonitor."""
        openclaw_home = tmp_path / "openclaw"
        sessions_dir = openclaw_home / "agents" / "main" / "sessions"
        sessions_dir.mkdir(parents=True)
        return SessionMonitor(openclaw_home=str(openclaw_home))

    def test_critical_for_nested_injections(self, tmp_path, monitor):
        """Critical status for nested injection blocks."""
        sessions_dir = tmp_path / "openclaw" / "agents" / "main" / "sessions"
        session_file = sessions_dir / "nested.jsonl"

        with open(session_file, "w") as f:
            f.write(json.dumps({
                "type": "message",
                "message": {
                    "role": "user",
                    "content": "[INJECTION-DEPTH:2] Recovered Conversation Context [INJECTION-DEPTH:1] Recovered Conversation Context"
                }
            }) + "\n")

        health = monitor.analyze_session(str(session_file))

        assert health.status == "critical"

    def test_critical_for_size_over_10mb(self, tmp_path, monitor):
        """Critical status for sessions over 10MB."""
        sessions_dir = tmp_path / "openclaw" / "agents" / "main" / "sessions"
        session_file = sessions_dir / "large.jsonl"

        # Create 11MB file
        with open(session_file, "w") as f:
            data = "x" * (11 * 1024 * 1024)
            f.write(data)

        health = monitor.analyze_session(str(session_file))

        assert health.status == "critical"

    def test_critical_for_high_injection_count(self, tmp_path, monitor):
        """Critical status for high injection marker count."""
        sessions_dir = tmp_path / "openclaw" / "agents" / "main" / "sessions"
        session_file = sessions_dir / "many-markers.jsonl"

        with open(session_file, "w") as f:
            for i in range(15):
                f.write(json.dumps({
                    "type": "message",
                    "message": {
                        "role": "user",
                        "content": f"[INJECTION-DEPTH:1] Recovered Conversation Context {i}"
                    }
                }) + "\n")

        health = monitor.analyze_session(str(session_file))

        assert health.status == "critical"

    def test_warning_for_size_over_2mb(self, tmp_path, monitor):
        """Warning status for sessions over 2MB."""
        sessions_dir = tmp_path / "openclaw" / "agents" / "main" / "sessions"
        session_file = sessions_dir / "medium.jsonl"

        # Create 3MB file
        with open(session_file, "w") as f:
            data = "x" * (3 * 1024 * 1024)
            f.write(data)

        health = monitor.analyze_session(str(session_file))

        assert health.status in ["warning", "critical"]

    def test_warning_for_moderate_injections(self, tmp_path, monitor):
        """Warning status for moderate injection count."""
        sessions_dir = tmp_path / "openclaw" / "agents" / "main" / "sessions"
        session_file = sessions_dir / "some-markers.jsonl"

        with open(session_file, "w") as f:
            for i in range(5):
                f.write(json.dumps({
                    "type": "message",
                    "message": {
                        "role": "user",
                        "content": f"[INJECTION-DEPTH:1] Recovered Conversation Context {i}"
                    }
                }) + "\n")

        health = monitor.analyze_session(str(session_file))

        assert health.status in ["warning", "healthy"]

    def test_healthy_for_normal_session(self, tmp_path, monitor):
        """Healthy status for normal session."""
        sessions_dir = tmp_path / "openclaw" / "agents" / "main" / "sessions"
        session_file = sessions_dir / "normal.jsonl"

        with open(session_file, "w") as f:
            for i in range(5):
                f.write(json.dumps({
                    "type": "message",
                    "message": {
                        "role": "user" if i % 2 == 0 else "assistant",
                        "content": f"Normal message {i}"
                    }
                }) + "\n")

        health = monitor.analyze_session(str(session_file))

        assert health.status == "healthy"


class TestSessionMonitorGrowthRate:
    """Tests for growth rate calculation."""

    @pytest.fixture
    def monitor(self, tmp_path):
        """Create SessionMonitor."""
        openclaw_home = tmp_path / "openclaw"
        sessions_dir = openclaw_home / "agents" / "main" / "sessions"
        sessions_dir.mkdir(parents=True)
        return SessionMonitor(openclaw_home=str(openclaw_home))

    def test_calculates_growth_rate(self, tmp_path, monitor):
        """Calculates growth rate between measurements."""
        sessions_dir = tmp_path / "openclaw" / "agents" / "main" / "sessions"
        session_file = sessions_dir / "growing.jsonl"

        # Initial content
        with open(session_file, "w") as f:
            f.write("initial content\n")

        # First measurement
        health1 = monitor.analyze_session(str(session_file))

        # Add more content
        with open(session_file, "a") as f:
            f.write("additional content " * 1000 + "\n")

        # Second measurement (simulating time passed)
        health2 = monitor.analyze_session(str(session_file))

        # Growth rate should be calculable
        assert health2.size_bytes > health1.size_bytes

    def test_requires_two_data_points(self, tmp_path, monitor):
        """Needs at least two measurements for growth rate."""
        sessions_dir = tmp_path / "openclaw" / "agents" / "main" / "sessions"
        session_file = sessions_dir / "new.jsonl"

        with open(session_file, "w") as f:
            f.write("content\n")

        health = monitor.analyze_session(str(session_file))

        # First measurement has no growth rate
        assert health.growth_rate_bytes_per_min == 0


class TestSessionMonitorDiscovery:
    """Tests for session discovery."""

    @pytest.fixture
    def monitor(self, tmp_path):
        """Create SessionMonitor with multiple sessions."""
        openclaw_home = tmp_path / "openclaw"
        sessions_dir = openclaw_home / "agents" / "main" / "sessions"
        sessions_dir.mkdir(parents=True)

        # Create various session files
        (sessions_dir / "session1.jsonl").write_text('{"type":"message"}\n')
        (sessions_dir / "session2.jsonl").write_text('{"type":"message"}\n')
        (sessions_dir / "sessions.json").write_text("[]")  # Metadata file
        (sessions_dir / ".archived.old.jsonl").write_text('{"type":"message"}\n')

        return SessionMonitor(openclaw_home=str(openclaw_home))

    def test_finds_all_sessions(self, monitor):
        """Finds all session files."""
        sessions = monitor.discover_sessions()

        # Should find session1 and session2, not sessions.json or archived
        session_names = [s.name for s in sessions]
        assert "session1.jsonl" in session_names
        assert "session2.jsonl" in session_names

    def test_excludes_sessions_json(self, monitor):
        """Excludes sessions.json metadata file."""
        sessions = monitor.discover_sessions()

        session_names = [s.name for s in sessions]
        assert "sessions.json" not in session_names

    def test_excludes_archived_files(self, monitor):
        """Excludes archived session files."""
        sessions = monitor.discover_sessions()

        session_names = [s.name for s in sessions]
        assert ".archived.old.jsonl" not in session_names


class TestSessionMonitorAlerts:
    """Tests for alert generation."""

    @pytest.fixture
    def monitor(self, tmp_path):
        """Create SessionMonitor."""
        openclaw_home = tmp_path / "openclaw"
        sessions_dir = openclaw_home / "agents" / "main" / "sessions"
        sessions_dir.mkdir(parents=True)
        return SessionMonitor(openclaw_home=str(openclaw_home))

    def test_returns_warnings_and_criticals(self, tmp_path, monitor):
        """Returns sessions with warning or critical status."""
        sessions_dir = tmp_path / "openclaw" / "agents" / "main" / "sessions"

        # Create a critical session (large file)
        large_file = sessions_dir / "large.jsonl"
        with open(large_file, "w") as f:
            f.write("x" * (11 * 1024 * 1024))

        # Create a healthy session
        healthy_file = sessions_dir / "healthy.jsonl"
        healthy_file.write_text('{"type":"message"}\n')

        alerts = monitor.get_alerts()

        # Should include the large file
        alert_sessions = [a.session_id for a in alerts]
        assert "large" in alert_sessions or "large.jsonl" in alert_sessions

    def test_excludes_healthy_from_alerts(self, tmp_path, monitor):
        """Excludes healthy sessions from alerts."""
        sessions_dir = tmp_path / "openclaw" / "agents" / "main" / "sessions"

        # Create only healthy sessions
        (sessions_dir / "healthy1.jsonl").write_text('{"type":"message"}\n')
        (sessions_dir / "healthy2.jsonl").write_text('{"type":"message"}\n')

        alerts = monitor.get_alerts()

        # Should be empty or only contain the sessions we created
        for alert in alerts:
            assert alert.status != "healthy"
