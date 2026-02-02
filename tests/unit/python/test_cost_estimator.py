#!/usr/bin/env python3
"""
Tests for lib/core/cost_estimator.py
"""

import json
import os
import sys
import tempfile
from datetime import datetime
from pathlib import Path
from unittest.mock import MagicMock, patch, mock_open

import pytest

# Add lib/core to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "lib" / "core"))

from cost_estimator import Cost, CostEstimator


class TestCost:
    """Tests for the Cost dataclass."""

    def test_auto_calculates_total(self):
        """Total is calculated from components when not provided."""
        cost = Cost(
            input_cost=0.01,
            output_cost=0.02,
            cache_read_cost=0.001,
            cache_write_cost=0.002
        )
        assert cost.total == pytest.approx(0.033, rel=1e-3)

    def test_explicit_total_overrides(self):
        """Explicit total overrides auto-calculation."""
        cost = Cost(
            input_cost=0.01,
            output_cost=0.02,
            cache_read_cost=0.001,
            cache_write_cost=0.002,
            total=0.05  # Explicit override
        )
        assert cost.total == 0.05

    def test_zero_costs(self):
        """Handles zero costs correctly."""
        cost = Cost(
            input_cost=0.0,
            output_cost=0.0,
            cache_read_cost=0.0,
            cache_write_cost=0.0
        )
        assert cost.total == 0.0


class TestCostEstimatorPricing:
    """Tests for pricing loading and model resolution."""

    def test_loads_pricing_from_file(self, tmp_path):
        """Loads pricing data from JSON file."""
        pricing_file = tmp_path / "pricing.json"
        pricing_data = {
            "models": {
                "claude-sonnet-4-20250514": {
                    "input_per_mtok": 3.0,
                    "output_per_mtok": 15.0,
                    "cache_read_per_mtok": 0.30,
                    "cache_write_per_mtok": 3.75
                }
            }
        }
        pricing_file.write_text(json.dumps(pricing_data))

        estimator = CostEstimator(pricing_path=str(pricing_file))

        assert "claude-sonnet-4-20250514" in estimator.pricing["models"]

    def test_falls_back_to_defaults_when_file_missing(self, tmp_path):
        """Uses default pricing when file doesn't exist."""
        fake_path = tmp_path / "nonexistent.json"
        estimator = CostEstimator(pricing_path=str(fake_path))

        # Should have default pricing
        assert "models" in estimator.pricing
        assert len(estimator.pricing["models"]) > 0

    def test_resolves_model_aliases(self, tmp_path):
        """Resolves model aliases to canonical names."""
        pricing_file = tmp_path / "pricing.json"
        pricing_data = {
            "models": {
                "claude-sonnet-4-20250514": {
                    "input_per_mtok": 3.0,
                    "output_per_mtok": 15.0
                }
            },
            "aliases": {
                "sonnet": "claude-sonnet-4-20250514",
                "claude-4-sonnet": "claude-sonnet-4-20250514"
            }
        }
        pricing_file.write_text(json.dumps(pricing_data))

        estimator = CostEstimator(pricing_path=str(pricing_file))

        # Should resolve alias
        resolved = estimator._resolve_model("sonnet")
        assert resolved == "claude-sonnet-4-20250514"


class TestCostEstimatorCalculation:
    """Tests for cost calculation."""

    @pytest.fixture
    def estimator(self, tmp_path):
        """Create estimator with known pricing."""
        pricing_file = tmp_path / "pricing.json"
        pricing_data = {
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
                }
            }
        }
        pricing_file.write_text(json.dumps(pricing_data))
        return CostEstimator(pricing_path=str(pricing_file), costs_dir=str(tmp_path / "costs"))

    def test_calculates_input_cost(self, estimator):
        """Calculates input token cost correctly."""
        # 1000 tokens at $3/Mtok = $0.003
        usage = {"input_tokens": 1000}
        cost = estimator.calculate("claude-sonnet-4-20250514", usage)

        assert cost.input_cost == pytest.approx(0.003, rel=1e-3)

    def test_calculates_output_cost(self, estimator):
        """Calculates output token cost correctly."""
        # 1000 tokens at $15/Mtok = $0.015
        usage = {"output_tokens": 1000}
        cost = estimator.calculate("claude-sonnet-4-20250514", usage)

        assert cost.output_cost == pytest.approx(0.015, rel=1e-3)

    def test_calculates_cache_read_cost(self, estimator):
        """Calculates cache read cost correctly."""
        # 1000 tokens at $0.30/Mtok = $0.0003
        usage = {"cache_read_input_tokens": 1000}
        cost = estimator.calculate("claude-sonnet-4-20250514", usage)

        assert cost.cache_read_cost == pytest.approx(0.0003, rel=1e-3)

    def test_calculates_cache_write_cost(self, estimator):
        """Calculates cache write cost correctly."""
        # 1000 tokens at $3.75/Mtok = $0.00375
        usage = {"cache_creation_input_tokens": 1000}
        cost = estimator.calculate("claude-sonnet-4-20250514", usage)

        assert cost.cache_write_cost == pytest.approx(0.00375, rel=1e-3)

    def test_subtracts_cached_from_input(self, estimator):
        """Input cost accounts for cached tokens."""
        # 2000 input, 500 cached read, 500 cached write
        # Billable input = 2000 - 500 - 500 = 1000
        usage = {
            "input_tokens": 2000,
            "cache_read_input_tokens": 500,
            "cache_creation_input_tokens": 500
        }
        cost = estimator.calculate("claude-sonnet-4-20250514", usage)

        # 1000 billable at $3/Mtok = $0.003
        assert cost.input_cost == pytest.approx(0.003, rel=1e-3)

    def test_handles_zero_tokens(self, estimator):
        """Handles zero token usage."""
        usage = {
            "input_tokens": 0,
            "output_tokens": 0
        }
        cost = estimator.calculate("claude-sonnet-4-20250514", usage)

        assert cost.total == 0.0

    def test_handles_missing_usage(self, estimator):
        """Handles missing usage fields."""
        usage = {}  # Empty usage
        cost = estimator.calculate("claude-sonnet-4-20250514", usage)

        assert cost.total == 0.0


class TestCostEstimatorRecording:
    """Tests for cost recording."""

    @pytest.fixture
    def estimator(self, tmp_path):
        """Create estimator with temp costs directory."""
        costs_dir = tmp_path / "costs"
        costs_dir.mkdir()
        return CostEstimator(costs_dir=str(costs_dir))

    def test_creates_costs_directory(self, tmp_path):
        """Creates costs directory if it doesn't exist."""
        costs_dir = tmp_path / "new_costs"
        estimator = CostEstimator(costs_dir=str(costs_dir))

        estimator.record(
            model="claude-sonnet-4-20250514",
            usage={"input_tokens": 100},
            session_id="test-session"
        )

        assert costs_dir.exists()

    def test_appends_to_daily_file(self, estimator, tmp_path):
        """Appends costs to daily JSONL file."""
        costs_dir = tmp_path / "costs"

        estimator.record(
            model="claude-sonnet-4-20250514",
            usage={"input_tokens": 100},
            session_id="test-session"
        )

        today = datetime.now().strftime("%Y-%m-%d")
        cost_file = costs_dir / f"costs-{today}.jsonl"

        assert cost_file.exists()

        with open(cost_file) as f:
            line = f.readline()
            data = json.loads(line)
            assert "timestamp" in data
            assert "model" in data

    def test_includes_session_id(self, estimator, tmp_path):
        """Recorded cost includes session ID."""
        costs_dir = tmp_path / "costs"

        estimator.record(
            model="claude-sonnet-4-20250514",
            usage={"input_tokens": 100},
            session_id="my-session-123"
        )

        today = datetime.now().strftime("%Y-%m-%d")
        cost_file = costs_dir / f"costs-{today}.jsonl"

        with open(cost_file) as f:
            data = json.loads(f.readline())
            assert data["session_id"] == "my-session-123"

    def test_generates_iso_timestamp(self, estimator, tmp_path):
        """Recorded cost has ISO timestamp."""
        costs_dir = tmp_path / "costs"

        estimator.record(
            model="claude-sonnet-4-20250514",
            usage={"input_tokens": 100},
            session_id="test"
        )

        today = datetime.now().strftime("%Y-%m-%d")
        cost_file = costs_dir / f"costs-{today}.jsonl"

        with open(cost_file) as f:
            data = json.loads(f.readline())
            # Should be ISO format
            assert "T" in data["timestamp"]
            assert "-" in data["timestamp"]


class TestCostEstimatorSummary:
    """Tests for cost summary/aggregation."""

    @pytest.fixture
    def estimator_with_data(self, tmp_path):
        """Create estimator with sample cost data."""
        costs_dir = tmp_path / "costs"
        costs_dir.mkdir()

        today = datetime.now().strftime("%Y-%m-%d")
        cost_file = costs_dir / f"costs-{today}.jsonl"

        with open(cost_file, "w") as f:
            f.write(json.dumps({
                "timestamp": "2026-01-15T10:00:00",
                "model": "claude-sonnet-4-20250514",
                "total_cost": 0.05
            }) + "\n")
            f.write(json.dumps({
                "timestamp": "2026-01-15T11:00:00",
                "model": "claude-sonnet-4-20250514",
                "total_cost": 0.03
            }) + "\n")

        return CostEstimator(costs_dir=str(costs_dir))

    def test_returns_zeros_for_missing_file(self, tmp_path):
        """Returns zeros when cost file doesn't exist."""
        costs_dir = tmp_path / "empty_costs"
        costs_dir.mkdir()
        estimator = CostEstimator(costs_dir=str(costs_dir))

        summary = estimator.get_daily_summary()

        assert summary["total_cost"] == 0.0
        assert summary["request_count"] == 0

    def test_aggregates_daily_costs(self, estimator_with_data):
        """Aggregates costs from daily file."""
        summary = estimator_with_data.get_daily_summary()

        assert summary["total_cost"] == pytest.approx(0.08, rel=1e-3)

    def test_counts_requests(self, estimator_with_data):
        """Counts total requests."""
        summary = estimator_with_data.get_daily_summary()

        assert summary["request_count"] == 2

    def test_skips_malformed_lines(self, tmp_path):
        """Skips malformed JSON lines."""
        costs_dir = tmp_path / "costs"
        costs_dir.mkdir()

        today = datetime.now().strftime("%Y-%m-%d")
        cost_file = costs_dir / f"costs-{today}.jsonl"

        with open(cost_file, "w") as f:
            f.write(json.dumps({"total_cost": 0.05}) + "\n")
            f.write("invalid json line\n")
            f.write(json.dumps({"total_cost": 0.03}) + "\n")

        estimator = CostEstimator(costs_dir=str(costs_dir))
        summary = estimator.get_daily_summary()

        # Should skip invalid line and sum valid ones
        assert summary["total_cost"] == pytest.approx(0.08, rel=1e-3)
        assert summary["request_count"] == 2


class TestCostEstimatorSavings:
    """Tests for savings estimation."""

    @pytest.fixture
    def estimator(self, tmp_path):
        """Create estimator."""
        return CostEstimator(costs_dir=str(tmp_path / "costs"))

    def test_estimates_savings_with_caching(self, estimator):
        """Estimates savings from prompt caching."""
        base_cost = 1.00
        savings = estimator.estimate_savings(
            base_cost=base_cost,
            caching_enabled=True,
            tiering_enabled=False
        )

        # Caching should save 25-40%
        assert savings["savings_percent"] >= 25
        assert savings["savings_percent"] <= 40

    def test_estimates_savings_with_tiering(self, estimator):
        """Estimates savings from model tiering."""
        base_cost = 1.00
        savings = estimator.estimate_savings(
            base_cost=base_cost,
            caching_enabled=False,
            tiering_enabled=True
        )

        # Tiering should save 35-50%
        assert savings["savings_percent"] >= 35
        assert savings["savings_percent"] <= 50

    def test_estimates_combined_savings(self, estimator):
        """Estimates combined savings."""
        base_cost = 1.00
        savings = estimator.estimate_savings(
            base_cost=base_cost,
            caching_enabled=True,
            tiering_enabled=True
        )

        # Combined should be > either alone but not additive
        assert savings["savings_percent"] >= 50
        assert savings["savings_percent"] <= 75

    def test_handles_zero_base_cost(self, estimator):
        """Handles zero base cost."""
        savings = estimator.estimate_savings(
            base_cost=0.0,
            caching_enabled=True,
            tiering_enabled=True
        )

        assert savings["estimated_cost"] == 0.0
        assert savings["savings_amount"] == 0.0
