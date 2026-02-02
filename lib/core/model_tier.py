#!/usr/bin/env python3
"""
OCTO Model Tier
Intelligent model selection based on request classification.
"""

import re
import json
import os
from pathlib import Path
from typing import Optional, List, Dict, Any
from dataclasses import dataclass

# Default paths
OCTO_HOME = Path(os.environ.get('OCTO_HOME', Path.home() / '.octo'))
LIB_DIR = Path(__file__).parent.parent


@dataclass
class TierDecision:
    """Result of model tier classification."""
    recommended_model: str
    confidence: float  # 0.0 - 1.0
    reason: str
    patterns_matched: List[str]


class ModelTier:
    """Classify requests and recommend optimal model tier."""

    # Default patterns for each tier
    DEFAULT_HAIKU_PATTERNS = [
        # Simple questions
        r"^(what|which|where|when|who|how many)\b",
        # File operations (simple)
        r"\b(list|show|display|get)\s+(files?|dirs?|folders?)",
        # Confirmations
        r"^(yes|no|confirm|cancel|ok|done|thanks?|thank you)\b",
        # Tool selection
        r"\buse\s+(the\s+)?(grep|glob|read|bash)\s+tool",
        # Simple status checks
        r"^(check|verify|validate|test)\s+(if|that|whether)",
        # Navigation
        r"^(go to|open|navigate|cd)\s+",
    ]

    DEFAULT_OPUS_PATTERNS = [
        # Architecture and design
        r"\b(architect|design|plan)\b.*\b(system|service|infrastructure|api)",
        # Trade-off analysis
        r"\b(trade-?off|compare|evaluate|contrast)\b.*\b(approach|solution|option|method)",
        # Security review
        r"\b(security|vulnerability|attack|threat)\b.*\b(audit|review|assess|analyze)",
        # Performance optimization
        r"\b(optimize|performance|scalability)\b.*\b(system|architecture|design)",
        # Complex debugging
        r"\b(debug|investigate|diagnose)\b.*\b(complex|mysterious|intermittent)",
    ]

    DEFAULT_SONNET_PATTERNS = [
        # Code generation
        r"\b(write|create|implement|build|add|generate)\b.*\b(function|class|method|api|component)",
        # Bug fixes
        r"\b(fix|debug|solve|resolve|repair)\b.*\b(bug|error|issue|problem)",
        # Refactoring
        r"\b(refactor|restructure|reorganize|clean up|improve)\b",
        # Testing
        r"\b(test|spec|coverage|unit test|integration test)\b",
        # Documentation
        r"\b(document|explain|describe)\b.*\b(code|function|class|api)",
    ]

    def __init__(self, config_path: Optional[Path] = None):
        """Initialize with optional custom config."""
        self.config = self._load_config(config_path)
        self._compile_patterns()

    def _load_config(self, config_path: Optional[Path] = None) -> Dict[str, Any]:
        """Load configuration from file or use defaults."""
        if config_path and config_path.exists():
            with open(config_path) as f:
                return json.load(f)

        # Try default config location
        default_config = OCTO_HOME / 'config.json'
        if default_config.exists():
            with open(default_config) as f:
                full_config = json.load(f)
                return full_config.get('optimization', {}).get('modelTiering', {})

        return {}

    def _compile_patterns(self):
        """Compile regex patterns for efficient matching."""
        config = self.config

        # Get patterns from config or use defaults
        haiku_patterns = config.get('haikuPatterns', self.DEFAULT_HAIKU_PATTERNS)
        opus_patterns = config.get('opusPatterns', self.DEFAULT_OPUS_PATTERNS)
        sonnet_patterns = config.get('sonnetPatterns', self.DEFAULT_SONNET_PATTERNS)

        # Compile patterns
        self.haiku_patterns = [(p, re.compile(p, re.IGNORECASE)) for p in haiku_patterns]
        self.opus_patterns = [(p, re.compile(p, re.IGNORECASE)) for p in opus_patterns]
        self.sonnet_patterns = [(p, re.compile(p, re.IGNORECASE)) for p in sonnet_patterns]

    def classify(self, message: str, context: Optional[Dict[str, Any]] = None) -> TierDecision:
        """
        Classify a message and recommend optimal model tier.

        Args:
            message: The user's message/prompt
            context: Optional context (e.g., conversation history, session info)

        Returns:
            TierDecision with recommended model and reasoning
        """
        message = message.strip()
        matched_patterns = []

        # Check Haiku patterns first (cheapest)
        for pattern_str, pattern in self.haiku_patterns:
            if pattern.search(message):
                matched_patterns.append(f"haiku:{pattern_str}")

        if matched_patterns:
            return TierDecision(
                recommended_model='haiku',
                confidence=0.85,
                reason='Simple query/operation detected',
                patterns_matched=matched_patterns,
            )

        # Check Opus patterns (most expensive, for complex tasks)
        for pattern_str, pattern in self.opus_patterns:
            if pattern.search(message):
                matched_patterns.append(f"opus:{pattern_str}")

        if matched_patterns:
            return TierDecision(
                recommended_model='opus',
                confidence=0.80,
                reason='Complex reasoning/architecture task detected',
                patterns_matched=matched_patterns,
            )

        # Check Sonnet patterns
        for pattern_str, pattern in self.sonnet_patterns:
            if pattern.search(message):
                matched_patterns.append(f"sonnet:{pattern_str}")

        if matched_patterns:
            return TierDecision(
                recommended_model='sonnet',
                confidence=0.90,
                reason='Code generation/modification task detected',
                patterns_matched=matched_patterns,
            )

        # Default to Sonnet for unclassified tasks (best balance)
        return TierDecision(
            recommended_model=self.config.get('defaultModel', 'sonnet'),
            confidence=0.60,
            reason='No specific patterns matched, using default',
            patterns_matched=[],
        )

    def should_tier(self, current_model: str, recommended_model: str, min_confidence: float = 0.7) -> bool:
        """
        Determine if we should switch to a different model tier.

        Args:
            current_model: The currently selected model
            recommended_model: The recommended model from classification
            min_confidence: Minimum confidence to recommend a tier change

        Returns:
            True if tiering should be applied
        """
        if not self.config.get('enabled', True):
            return False

        # Don't downgrade from Opus unless highly confident
        if 'opus' in current_model.lower() and recommended_model != 'opus':
            return False

        return True


def main():
    """CLI interface for model tiering."""
    import sys

    tier = ModelTier()

    if len(sys.argv) > 1:
        message = ' '.join(sys.argv[1:])
        decision = tier.classify(message)

        print(f"Recommended model: {decision.recommended_model}")
        print(f"Confidence: {decision.confidence:.0%}")
        print(f"Reason: {decision.reason}")
        if decision.patterns_matched:
            print(f"Patterns matched: {', '.join(decision.patterns_matched)}")
    else:
        print("Usage: model_tier.py <message>")
        print("")
        print("Examples:")
        print("  model_tier.py 'What files are in this directory?'")
        print("  model_tier.py 'Write a function to parse JSON'")
        print("  model_tier.py 'Design the authentication system architecture'")


if __name__ == '__main__':
    main()
