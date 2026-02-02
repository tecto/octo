#!/usr/bin/env python3
"""
OCTO Cost Estimator
Real-time cost calculation and tracking for OpenClaw API usage.
"""

import json
import os
from datetime import datetime, date
from pathlib import Path
from dataclasses import dataclass, asdict
from typing import Optional, Dict, Any

# Default paths
OCTO_HOME = Path(os.environ.get('OCTO_HOME', Path.home() / '.octo'))
LIB_DIR = Path(__file__).parent.parent

# Load pricing
PRICING_FILE = LIB_DIR / 'config' / 'model_pricing.json'


@dataclass
class Cost:
    """Cost breakdown for a single request."""
    input_cost: float = 0.0
    output_cost: float = 0.0
    cache_read_cost: float = 0.0
    cache_write_cost: float = 0.0
    total: float = 0.0

    def __post_init__(self):
        if self.total == 0.0:
            self.total = (
                self.input_cost +
                self.output_cost +
                self.cache_read_cost +
                self.cache_write_cost
            )


@dataclass
class RequestCost:
    """Full cost record for a request."""
    timestamp: str
    model: str
    input_tokens: int
    output_tokens: int
    cache_read_tokens: int
    cache_write_tokens: int
    cost: Cost
    session_id: Optional[str] = None

    @property
    def total(self) -> float:
        return self.cost.total


class CostEstimator:
    """Calculate and track API costs."""

    def __init__(self):
        self.pricing = self._load_pricing()
        self.costs_dir = OCTO_HOME / 'costs'
        self.costs_dir.mkdir(parents=True, exist_ok=True)

    def _load_pricing(self) -> Dict[str, Any]:
        """Load pricing data from config file."""
        if PRICING_FILE.exists():
            with open(PRICING_FILE) as f:
                return json.load(f)
        return {
            'models': {
                'claude-sonnet-4-20250514': {
                    'input_per_million': 3.00,
                    'output_per_million': 15.00,
                    'cache_read_per_million': 0.30,
                    'cache_write_per_million': 3.75,
                }
            },
            'aliases': {}
        }

    def _resolve_model(self, model: str) -> str:
        """Resolve model alias to full model ID."""
        aliases = self.pricing.get('aliases', {})
        return aliases.get(model, model)

    def _get_model_pricing(self, model: str) -> Dict[str, float]:
        """Get pricing for a model."""
        model_id = self._resolve_model(model)
        models = self.pricing.get('models', {})

        if model_id in models:
            return models[model_id]

        # Default to Sonnet pricing
        return models.get('claude-sonnet-4-20250514', {
            'input_per_million': 3.00,
            'output_per_million': 15.00,
            'cache_read_per_million': 0.30,
            'cache_write_per_million': 3.75,
        })

    def calculate(self, request: Dict[str, Any], response: Dict[str, Any]) -> RequestCost:
        """Calculate cost for a request/response pair."""
        model = response.get('model', 'claude-sonnet-4-20250514')
        pricing = self._get_model_pricing(model)

        usage = response.get('usage', {})
        input_tokens = usage.get('input_tokens', 0)
        output_tokens = usage.get('output_tokens', 0)
        cache_read = usage.get('cache_read_input_tokens', 0)
        cache_write = usage.get('cache_creation_input_tokens', 0)

        # Actual input = total - cached
        actual_input = max(0, input_tokens - cache_read)

        cost = Cost(
            input_cost=(actual_input / 1_000_000) * pricing['input_per_million'],
            output_cost=(output_tokens / 1_000_000) * pricing['output_per_million'],
            cache_read_cost=(cache_read / 1_000_000) * pricing['cache_read_per_million'],
            cache_write_cost=(cache_write / 1_000_000) * pricing['cache_write_per_million'],
        )

        return RequestCost(
            timestamp=datetime.utcnow().isoformat() + 'Z',
            model=model,
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            cache_read_tokens=cache_read,
            cache_write_tokens=cache_write,
            cost=cost,
        )

    def record(self, request_cost: RequestCost, session_id: Optional[str] = None):
        """Record a cost to the daily log file."""
        request_cost.session_id = session_id

        today = date.today().isoformat()
        cost_file = self.costs_dir / f'{today}.jsonl'

        record = {
            'timestamp': request_cost.timestamp,
            'model': request_cost.model,
            'input_tokens': request_cost.input_tokens,
            'output_tokens': request_cost.output_tokens,
            'cache_read_tokens': request_cost.cache_read_tokens,
            'cache_write_tokens': request_cost.cache_write_tokens,
            'input_cost': request_cost.cost.input_cost,
            'output_cost': request_cost.cost.output_cost,
            'cache_read_cost': request_cost.cost.cache_read_cost,
            'cache_write_cost': request_cost.cost.cache_write_cost,
            'total': request_cost.total,
            'session_id': session_id,
        }

        with open(cost_file, 'a') as f:
            f.write(json.dumps(record) + '\n')

    def get_daily_summary(self, day: Optional[date] = None) -> Dict[str, Any]:
        """Get cost summary for a specific day."""
        if day is None:
            day = date.today()

        cost_file = self.costs_dir / f'{day.isoformat()}.jsonl'

        if not cost_file.exists():
            return {
                'date': day.isoformat(),
                'requests': 0,
                'total_cost': 0.0,
                'input_tokens': 0,
                'output_tokens': 0,
                'cache_read_tokens': 0,
            }

        total_cost = 0.0
        total_requests = 0
        total_input = 0
        total_output = 0
        total_cached = 0

        with open(cost_file) as f:
            for line in f:
                try:
                    record = json.loads(line)
                    total_cost += record.get('total', 0)
                    total_requests += 1
                    total_input += record.get('input_tokens', 0)
                    total_output += record.get('output_tokens', 0)
                    total_cached += record.get('cache_read_tokens', 0)
                except json.JSONDecodeError:
                    continue

        return {
            'date': day.isoformat(),
            'requests': total_requests,
            'total_cost': total_cost,
            'input_tokens': total_input,
            'output_tokens': total_output,
            'cache_read_tokens': total_cached,
        }

    def estimate_savings(self, with_caching: bool = True, with_tiering: bool = True) -> Dict[str, float]:
        """Estimate savings from OCTO optimizations."""
        today = self.get_daily_summary()

        base_cost = today['total_cost']
        if base_cost == 0:
            return {'base_cost': 0, 'estimated_without_octo': 0, 'savings': 0, 'savings_percent': 0}

        # Estimate what cost would be without optimizations
        multiplier = 1.0
        if with_caching:
            # Caching typically saves 25-40%, so without it cost would be higher
            multiplier *= 1.4
        if with_tiering:
            # Tiering saves 20-35%
            multiplier *= 1.3

        estimated_without = base_cost * multiplier
        savings = estimated_without - base_cost

        return {
            'base_cost': base_cost,
            'estimated_without_octo': estimated_without,
            'savings': savings,
            'savings_percent': (savings / estimated_without * 100) if estimated_without > 0 else 0,
        }


def main():
    """CLI interface for cost estimator."""
    import sys

    estimator = CostEstimator()

    if len(sys.argv) > 1:
        cmd = sys.argv[1]

        if cmd == 'today':
            summary = estimator.get_daily_summary()
            print(json.dumps(summary, indent=2))

        elif cmd == 'savings':
            savings = estimator.estimate_savings()
            print(json.dumps(savings, indent=2))

        else:
            print(f"Unknown command: {cmd}")
            print("Usage: cost_estimator.py [today|savings]")
            sys.exit(1)
    else:
        summary = estimator.get_daily_summary()
        print(f"Today's cost: ${summary['total_cost']:.4f}")
        print(f"Requests: {summary['requests']}")
        print(f"Input tokens: {summary['input_tokens']}")
        print(f"Output tokens: {summary['output_tokens']}")
        print(f"Cached tokens: {summary['cache_read_tokens']}")


if __name__ == '__main__':
    main()
