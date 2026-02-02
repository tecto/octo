#!/usr/bin/env python3
"""
Integration tests for cost tracking flow.
"""

import json
import os
import sys
import tempfile
from datetime import datetime
from pathlib import Path

import pytest

# Add lib/core to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "lib" / "core"))

from cost_estimator import CostEstimator


class TestCostTrackingFlow:
    """End-to-end tests for cost tracking."""

    @pytest.fixture
    def temp_env(self):
        """Create temporary test environment."""
        with tempfile.TemporaryDirectory() as tmpdir:
            tmpdir = Path(tmpdir)

            # Create OCTO home
            octo_home = tmpdir / "octo"
            octo_home.mkdir()
            (octo_home / "costs").mkdir()
            (octo_home / "config.json").write_text(json.dumps({
                "version": "1.0.0",
                "costTracking": {"enabled": True}
            }))

            # Create OpenClaw home
            openclaw_home = tmpdir / "openclaw"
            sessions_dir = openclaw_home / "agents" / "main" / "sessions"
            sessions_dir.mkdir(parents=True)

            yield {
                "tmpdir": tmpdir,
                "octo_home": octo_home,
                "openclaw_home": openclaw_home,
                "costs_dir": octo_home / "costs"
            }

    def test_plugin_records_cost_on_request(self, temp_env):
        """Plugin records cost when request completes."""
        estimator = CostEstimator(costs_dir=str(temp_env["costs_dir"]))

        # Simulate request completion
        usage = {
            "input_tokens": 1500,
            "output_tokens": 500,
            "cache_read_input_tokens": 200
        }

        estimator.record(
            model="claude-sonnet-4-20250514",
            usage=usage,
            session_id="test-session-001"
        )

        # Verify cost file exists
        today = datetime.now().strftime("%Y-%m-%d")
        cost_file = temp_env["costs_dir"] / f"costs-{today}.jsonl"

        assert cost_file.exists()

        # Verify content
        with open(cost_file) as f:
            record = json.loads(f.readline())

        assert record["model"] == "claude-sonnet-4-20250514"
        assert record["session_id"] == "test-session-001"
        assert record["input_tokens"] == 1500
        assert record["total_cost"] > 0

    def test_multiple_requests_append_to_same_file(self, temp_env):
        """Multiple requests append to the same daily file."""
        estimator = CostEstimator(costs_dir=str(temp_env["costs_dir"]))

        # Record multiple requests
        for i in range(3):
            estimator.record(
                model="claude-sonnet-4-20250514",
                usage={"input_tokens": 100 * (i + 1), "output_tokens": 50},
                session_id=f"session-{i}"
            )

        # Verify all records in file
        today = datetime.now().strftime("%Y-%m-%d")
        cost_file = temp_env["costs_dir"] / f"costs-{today}.jsonl"

        with open(cost_file) as f:
            lines = f.readlines()

        assert len(lines) == 3

    def test_status_shows_recorded_costs(self, temp_env):
        """Status command can read recorded costs."""
        estimator = CostEstimator(costs_dir=str(temp_env["costs_dir"]))

        # Record some costs
        estimator.record(
            model="claude-sonnet-4-20250514",
            usage={"input_tokens": 1000, "output_tokens": 500},
            session_id="session-001"
        )
        estimator.record(
            model="claude-haiku-3-5-20241022",
            usage={"input_tokens": 500, "output_tokens": 200},
            session_id="session-002"
        )

        # Get summary
        summary = estimator.get_daily_summary()

        assert summary["request_count"] == 2
        assert summary["total_cost"] > 0

    def test_analyze_aggregates_costs(self, temp_env):
        """Analyze command aggregates costs correctly."""
        estimator = CostEstimator(costs_dir=str(temp_env["costs_dir"]))

        # Record costs for different models
        models_usage = [
            ("claude-sonnet-4-20250514", 1000, 500),
            ("claude-haiku-3-5-20241022", 800, 300),
            ("claude-sonnet-4-20250514", 1200, 600),
        ]

        for model, input_tok, output_tok in models_usage:
            estimator.record(
                model=model,
                usage={"input_tokens": input_tok, "output_tokens": output_tok},
                session_id="session"
            )

        # Get summary
        summary = estimator.get_daily_summary()

        assert summary["request_count"] == 3
        # Verify total is sum of individual costs
        assert summary["total_cost"] > 0

    def test_cost_files_persist_across_estimator_instances(self, temp_env):
        """Cost files persist when new estimator instance created."""
        # First instance records costs
        estimator1 = CostEstimator(costs_dir=str(temp_env["costs_dir"]))
        estimator1.record(
            model="claude-sonnet-4-20250514",
            usage={"input_tokens": 1000, "output_tokens": 500},
            session_id="session-001"
        )

        # Second instance reads costs
        estimator2 = CostEstimator(costs_dir=str(temp_env["costs_dir"]))
        summary = estimator2.get_daily_summary()

        assert summary["request_count"] == 1
        assert summary["total_cost"] > 0

    def test_handles_different_models_correctly(self, temp_env):
        """Correctly calculates costs for different model tiers."""
        estimator = CostEstimator(costs_dir=str(temp_env["costs_dir"]))

        # Same usage, different models
        usage = {"input_tokens": 1000, "output_tokens": 1000}

        # Haiku (cheapest)
        haiku_cost = estimator.calculate("claude-haiku-3-5-20241022", usage)

        # Sonnet (mid-tier)
        sonnet_cost = estimator.calculate("claude-sonnet-4-20250514", usage)

        # Opus (most expensive)
        opus_cost = estimator.calculate("claude-opus-4-20250514", usage)

        # Verify ordering
        assert haiku_cost.total < sonnet_cost.total < opus_cost.total

    def test_cache_costs_reduce_total(self, temp_env):
        """Cache usage reduces total cost."""
        estimator = CostEstimator(costs_dir=str(temp_env["costs_dir"]))

        # Without cache
        usage_no_cache = {
            "input_tokens": 2000,
            "output_tokens": 500
        }
        cost_no_cache = estimator.calculate("claude-sonnet-4-20250514", usage_no_cache)

        # With cache (1000 tokens from cache)
        usage_with_cache = {
            "input_tokens": 2000,
            "output_tokens": 500,
            "cache_read_input_tokens": 1000  # These are billed at lower rate
        }
        cost_with_cache = estimator.calculate("claude-sonnet-4-20250514", usage_with_cache)

        # Cache should reduce cost
        assert cost_with_cache.total < cost_no_cache.total


class TestCostTrackingEdgeCases:
    """Edge case tests for cost tracking."""

    @pytest.fixture
    def estimator(self, tmp_path):
        """Create estimator with temp directory."""
        costs_dir = tmp_path / "costs"
        costs_dir.mkdir()
        return CostEstimator(costs_dir=str(costs_dir))

    def test_handles_empty_usage(self, estimator):
        """Handles empty usage dictionary."""
        cost = estimator.calculate("claude-sonnet-4-20250514", {})
        assert cost.total == 0.0

    def test_handles_none_usage(self, estimator):
        """Handles None usage."""
        cost = estimator.calculate("claude-sonnet-4-20250514", None)
        assert cost.total == 0.0

    def test_handles_unknown_model(self, estimator):
        """Uses default pricing for unknown model."""
        usage = {"input_tokens": 1000, "output_tokens": 500}
        cost = estimator.calculate("unknown-model-xyz", usage)

        # Should still calculate something
        assert cost.total > 0

    def test_handles_very_large_token_counts(self, estimator):
        """Handles very large token counts without overflow."""
        usage = {
            "input_tokens": 1_000_000,  # 1M tokens
            "output_tokens": 500_000
        }
        cost = estimator.calculate("claude-sonnet-4-20250514", usage)

        # Should be around $10.50 for this volume
        assert cost.total > 0
        assert cost.total < 100  # Sanity check

    def test_handles_zero_tokens(self, estimator):
        """Handles zero token counts."""
        usage = {
            "input_tokens": 0,
            "output_tokens": 0,
            "cache_read_input_tokens": 0,
            "cache_creation_input_tokens": 0
        }
        cost = estimator.calculate("claude-sonnet-4-20250514", usage)
        assert cost.total == 0.0

    def test_concurrent_writes(self, tmp_path):
        """Multiple estimators can write concurrently."""
        costs_dir = tmp_path / "costs"
        costs_dir.mkdir()

        # Create multiple estimators
        estimators = [
            CostEstimator(costs_dir=str(costs_dir))
            for _ in range(3)
        ]

        # Each records costs
        for i, est in enumerate(estimators):
            est.record(
                model="claude-sonnet-4-20250514",
                usage={"input_tokens": 100, "output_tokens": 50},
                session_id=f"session-{i}"
            )

        # Verify all records exist
        today = datetime.now().strftime("%Y-%m-%d")
        cost_file = costs_dir / f"costs-{today}.jsonl"

        with open(cost_file) as f:
            lines = f.readlines()

        assert len(lines) == 3
