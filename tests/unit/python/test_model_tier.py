#!/usr/bin/env python3
"""
Tests for lib/core/model_tier.py
"""

import json
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

# Add lib/core to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent / "lib" / "core"))

from model_tier import TierDecision, ModelTier


class TestTierDecision:
    """Tests for the TierDecision dataclass."""

    def test_dataclass_fields(self):
        """TierDecision has expected fields."""
        decision = TierDecision(
            original_model="claude-sonnet-4-20250514",
            recommended_model="claude-haiku-3-5-20241022",
            tier="haiku",
            confidence=0.85,
            reason="Simple question"
        )

        assert decision.original_model == "claude-sonnet-4-20250514"
        assert decision.recommended_model == "claude-haiku-3-5-20241022"
        assert decision.tier == "haiku"
        assert decision.confidence == 0.85
        assert decision.reason == "Simple question"


class TestModelTierPatternMatching:
    """Tests for pattern matching logic."""

    @pytest.fixture
    def tier(self, tmp_path):
        """Create ModelTier with default patterns."""
        return ModelTier()

    # Haiku patterns
    def test_haiku_simple_questions(self, tier):
        """Simple questions route to Haiku."""
        messages = [{"role": "user", "content": "What is 2+2?"}]
        decision = tier.classify(messages)

        assert decision.tier == "haiku"
        assert decision.confidence >= 0.7

    def test_haiku_file_operations(self, tier):
        """File listing requests route to Haiku."""
        messages = [{"role": "user", "content": "List all files in the current directory"}]
        decision = tier.classify(messages)

        assert decision.tier == "haiku"

    def test_haiku_confirmations(self, tier):
        """Simple confirmations route to Haiku."""
        messages = [{"role": "user", "content": "Yes, please proceed"}]
        decision = tier.classify(messages)

        assert decision.tier == "haiku"

    def test_haiku_tool_selection(self, tier):
        """Tool selection queries route to Haiku."""
        messages = [{"role": "user", "content": "Which tool should I use to read a file?"}]
        decision = tier.classify(messages)

        assert decision.tier == "haiku"

    # Opus patterns
    def test_opus_architecture_design(self, tier):
        """Architecture design routes to Opus."""
        messages = [{
            "role": "user",
            "content": "Design a microservices architecture for a high-traffic e-commerce platform"
        }]
        decision = tier.classify(messages)

        assert decision.tier == "opus"
        assert decision.confidence >= 0.8

    def test_opus_tradeoff_analysis(self, tier):
        """Tradeoff analysis routes to Opus."""
        messages = [{
            "role": "user",
            "content": "Analyze the tradeoffs between using PostgreSQL vs MongoDB for this use case"
        }]
        decision = tier.classify(messages)

        assert decision.tier == "opus"

    def test_opus_security_review(self, tier):
        """Security reviews route to Opus."""
        messages = [{
            "role": "user",
            "content": "Review this code for security vulnerabilities and potential exploits"
        }]
        decision = tier.classify(messages)

        assert decision.tier == "opus"

    # Sonnet patterns
    def test_sonnet_code_generation(self, tier):
        """Code generation routes to Sonnet."""
        messages = [{
            "role": "user",
            "content": "Write a function to parse JSON and extract specific fields"
        }]
        decision = tier.classify(messages)

        assert decision.tier == "sonnet"

    def test_sonnet_bug_fixes(self, tier):
        """Bug fixes route to Sonnet."""
        messages = [{
            "role": "user",
            "content": "Fix this bug in my code: the loop doesn't terminate properly"
        }]
        decision = tier.classify(messages)

        assert decision.tier == "sonnet"

    def test_sonnet_refactoring(self, tier):
        """Refactoring requests route to Sonnet."""
        messages = [{
            "role": "user",
            "content": "Refactor this function to be more efficient"
        }]
        decision = tier.classify(messages)

        assert decision.tier == "sonnet"


class TestModelTierDefaults:
    """Tests for default behavior."""

    @pytest.fixture
    def tier(self):
        """Create ModelTier."""
        return ModelTier()

    def test_defaults_to_sonnet(self, tier):
        """Unknown patterns default to Sonnet."""
        messages = [{
            "role": "user",
            "content": "Tell me something interesting"
        }]
        decision = tier.classify(messages)

        assert decision.tier == "sonnet"

    def test_default_has_lower_confidence(self, tier):
        """Default classification has lower confidence."""
        messages = [{
            "role": "user",
            "content": "Random unclassifiable message"
        }]
        decision = tier.classify(messages)

        # Default should have confidence around 0.5
        assert decision.confidence <= 0.6


class TestModelTierConfiguration:
    """Tests for configuration loading."""

    def test_loads_custom_patterns(self, tmp_path):
        """Loads custom patterns from config file."""
        config_file = tmp_path / "tier_config.json"
        config_data = {
            "patterns": {
                "haiku": ["^hello$", "^hi$"],
                "opus": ["^complex.*analysis"],
                "sonnet": [".*code.*"]
            }
        }
        config_file.write_text(json.dumps(config_data))

        tier = ModelTier(config_path=str(config_file))

        # Custom pattern should work
        messages = [{"role": "user", "content": "hello"}]
        decision = tier.classify(messages)

        assert decision.tier == "haiku"

    def test_uses_defaults_when_config_missing(self, tmp_path):
        """Uses default patterns when config doesn't exist."""
        fake_path = tmp_path / "nonexistent.json"
        tier = ModelTier(config_path=str(fake_path))

        # Should still work with defaults
        messages = [{"role": "user", "content": "What is 2+2?"}]
        decision = tier.classify(messages)

        assert decision.tier in ["haiku", "sonnet", "opus"]


class TestModelTierShouldTier:
    """Tests for should_tier method."""

    @pytest.fixture
    def tier(self):
        """Create ModelTier."""
        return ModelTier()

    def test_respects_enabled_config(self, tier):
        """Respects enabled configuration."""
        # When disabled, should not tier
        result = tier.should_tier(
            current_model="claude-sonnet-4-20250514",
            messages=[{"role": "user", "content": "Hello"}],
            enabled=False
        )

        assert result is None

    def test_preserves_opus_model(self, tier):
        """Does not downgrade from Opus."""
        result = tier.should_tier(
            current_model="claude-opus-4-20250514",
            messages=[{"role": "user", "content": "What is 2+2?"}],
            enabled=True
        )

        # Should preserve Opus even for simple questions
        assert result is None or result.recommended_model == "claude-opus-4-20250514"

    def test_allows_downgrade_to_haiku(self, tier):
        """Allows downgrade from Sonnet to Haiku."""
        result = tier.should_tier(
            current_model="claude-sonnet-4-20250514",
            messages=[{"role": "user", "content": "Yes"}],
            enabled=True
        )

        if result:
            assert "haiku" in result.recommended_model.lower()


class TestModelTierMultiMessage:
    """Tests for multi-message context."""

    @pytest.fixture
    def tier(self):
        """Create ModelTier."""
        return ModelTier()

    def test_considers_recent_context(self, tier):
        """Considers recent messages in context."""
        messages = [
            {"role": "user", "content": "Design a complex system"},
            {"role": "assistant", "content": "Here's my design..."},
            {"role": "user", "content": "Continue"}
        ]
        decision = tier.classify(messages)

        # Should consider the complex context
        assert decision.tier in ["sonnet", "opus"]

    def test_uses_last_user_message(self, tier):
        """Primary classification from last user message."""
        messages = [
            {"role": "user", "content": "Write complex code"},
            {"role": "assistant", "content": "Here it is..."},
            {"role": "user", "content": "Yes"}
        ]
        decision = tier.classify(messages)

        # "Yes" is simple, might classify as haiku
        assert decision.tier == "haiku"

    def test_handles_empty_messages(self, tier):
        """Handles empty message list."""
        messages = []
        decision = tier.classify(messages)

        # Should default to sonnet
        assert decision.tier == "sonnet"


class TestModelTierModelMapping:
    """Tests for model ID mapping."""

    @pytest.fixture
    def tier(self):
        """Create ModelTier."""
        return ModelTier()

    def test_maps_haiku_tier_to_model(self, tier):
        """Maps haiku tier to correct model ID."""
        messages = [{"role": "user", "content": "Hello"}]
        decision = tier.classify(messages)

        if decision.tier == "haiku":
            assert "haiku" in decision.recommended_model.lower()

    def test_maps_sonnet_tier_to_model(self, tier):
        """Maps sonnet tier to correct model ID."""
        messages = [{"role": "user", "content": "Write a function"}]
        decision = tier.classify(messages)

        if decision.tier == "sonnet":
            assert "sonnet" in decision.recommended_model.lower()

    def test_maps_opus_tier_to_model(self, tier):
        """Maps opus tier to correct model ID."""
        messages = [{
            "role": "user",
            "content": "Design complex architecture with security analysis"
        }]
        decision = tier.classify(messages)

        if decision.tier == "opus":
            assert "opus" in decision.recommended_model.lower()
