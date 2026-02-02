#!/usr/bin/env python3
"""
OCTO Session Monitor
Track session health, context utilization, and growth patterns.
"""

import json
import os
import re
from datetime import datetime
from pathlib import Path
from dataclasses import dataclass
from typing import Optional, List, Dict, Any

# Default paths
OCTO_HOME = Path(os.environ.get('OCTO_HOME', Path.home() / '.octo'))
OPENCLAW_HOME = Path(os.environ.get('OPENCLAW_HOME', Path.home() / '.openclaw'))


# Model context limits
MODEL_CONTEXT_LIMITS = {
    'claude-opus-4-5': 200000,
    'claude-sonnet-4': 200000,
    'claude-haiku-3-5': 200000,
    'default': 200000,
}


@dataclass
class SessionHealth:
    """Health status for a session."""
    session_id: str
    file_path: str
    file_size_bytes: int
    file_size_kb: int
    estimated_tokens: int
    context_utilization: float  # 0.0 - 1.0
    injection_count: int
    max_nested_injections: int
    message_count: int
    growth_rate_kb_per_min: float
    status: str  # HEALTHY, WARNING, CRITICAL
    recommendation: str


class SessionMonitor:
    """Monitor session health and detect issues."""

    # Thresholds
    WARNING_THRESHOLD = 0.70   # 70% of context window
    CRITICAL_THRESHOLD = 0.90  # 90% of context window
    SIZE_WARNING_KB = 2000     # 2MB
    SIZE_CRITICAL_KB = 10000   # 10MB
    GROWTH_RATE_WARN = 500     # KB per minute
    INJECTION_WARNING = 10
    INJECTION_CRITICAL = 50
    NESTED_INJECTION_WARNING = 1

    def __init__(self, sessions_dir: Optional[Path] = None):
        """Initialize session monitor."""
        self.sessions_dir = sessions_dir or (OPENCLAW_HOME / 'agents' / 'main' / 'sessions')
        self.size_history: Dict[str, List[tuple]] = {}  # session_id -> [(timestamp, size)]

    def analyze_session(self, session_file: Path) -> SessionHealth:
        """Analyze a single session file."""
        session_id = session_file.stem

        # Get file stats
        file_size = session_file.stat().st_size
        file_size_kb = file_size // 1024

        # Estimate tokens (rough: ~4 chars per token)
        estimated_tokens = file_size // 4

        # Parse session for detailed analysis
        injection_count = 0
        max_nested = 0
        message_count = 0
        model = 'default'

        try:
            with open(session_file, 'r') as f:
                for line in f:
                    try:
                        entry = json.loads(line)

                        if entry.get('type') == 'message':
                            message_count += 1
                            msg = entry.get('message', {})

                            # Track model
                            if 'model' in entry:
                                model = entry['model']

                            # Count injections in user messages
                            if msg.get('role') == 'user':
                                content = str(msg.get('content', ''))
                                # Count injection blocks
                                blocks = len(re.findall(
                                    r'\[INJECTION-DEPTH:[^\]]*\].{0,200}Recovered Conversation Context',
                                    content
                                ))
                                injection_count += blocks
                                max_nested = max(max_nested, blocks)

                    except json.JSONDecodeError:
                        continue
        except Exception:
            pass

        # Calculate context utilization
        context_limit = MODEL_CONTEXT_LIMITS.get(model, MODEL_CONTEXT_LIMITS['default'])
        context_utilization = estimated_tokens / context_limit

        # Calculate growth rate
        growth_rate = self._calculate_growth_rate(session_id, file_size_kb)

        # Determine status
        status = 'HEALTHY'
        recommendation = 'Session is healthy'

        if max_nested > self.NESTED_INJECTION_WARNING:
            status = 'CRITICAL'
            recommendation = f'Nested injection blocks detected ({max_nested}) - possible feedback loop'
        elif file_size_kb > self.SIZE_CRITICAL_KB:
            status = 'CRITICAL'
            recommendation = 'Session exceeds size limit - archive immediately'
        elif injection_count > self.INJECTION_CRITICAL:
            status = 'CRITICAL'
            recommendation = f'High injection count ({injection_count}) - possible bloat'
        elif context_utilization > self.CRITICAL_THRESHOLD:
            status = 'CRITICAL'
            recommendation = 'Context window nearly full - archive soon'
        elif file_size_kb > self.SIZE_WARNING_KB:
            status = 'WARNING'
            recommendation = 'Session growing large - monitor closely'
        elif injection_count > self.INJECTION_WARNING:
            status = 'WARNING'
            recommendation = f'Elevated injection count ({injection_count})'
        elif context_utilization > self.WARNING_THRESHOLD:
            status = 'WARNING'
            recommendation = 'Context utilization elevated'
        elif growth_rate > self.GROWTH_RATE_WARN:
            status = 'WARNING'
            recommendation = f'Rapid growth detected ({growth_rate:.0f} KB/min)'

        return SessionHealth(
            session_id=session_id,
            file_path=str(session_file),
            file_size_bytes=file_size,
            file_size_kb=file_size_kb,
            estimated_tokens=estimated_tokens,
            context_utilization=context_utilization,
            injection_count=injection_count,
            max_nested_injections=max_nested,
            message_count=message_count,
            growth_rate_kb_per_min=growth_rate,
            status=status,
            recommendation=recommendation,
        )

    def _calculate_growth_rate(self, session_id: str, current_size_kb: int) -> float:
        """Calculate growth rate in KB per minute."""
        now = datetime.now().timestamp()

        # Initialize or update history
        if session_id not in self.size_history:
            self.size_history[session_id] = []

        history = self.size_history[session_id]
        history.append((now, current_size_kb))

        # Keep only last 5 minutes of history
        cutoff = now - 300
        history = [(t, s) for t, s in history if t > cutoff]
        self.size_history[session_id] = history

        if len(history) < 2:
            return 0.0

        # Calculate rate from oldest to newest
        oldest_time, oldest_size = history[0]
        newest_time, newest_size = history[-1]

        time_diff = (newest_time - oldest_time) / 60  # Convert to minutes
        if time_diff < 0.1:  # Less than 6 seconds
            return 0.0

        size_diff = newest_size - oldest_size
        return max(0, size_diff / time_diff)

    def get_all_sessions(self) -> List[SessionHealth]:
        """Get health status for all active sessions."""
        sessions = []

        if not self.sessions_dir.exists():
            return sessions

        for f in self.sessions_dir.glob('*.jsonl'):
            if f.name == 'sessions.json':
                continue
            if '.archived.' in f.name:
                continue

            try:
                health = self.analyze_session(f)
                sessions.append(health)
            except Exception:
                continue

        return sessions

    def get_alerts(self) -> List[SessionHealth]:
        """Get sessions that need attention (WARNING or CRITICAL)."""
        return [s for s in self.get_all_sessions() if s.status != 'HEALTHY']

    def print_status(self):
        """Print status of all sessions."""
        sessions = self.get_all_sessions()

        if not sessions:
            print("No active sessions found")
            return

        print("\n" + "=" * 70)
        print("SESSION HEALTH STATUS")
        print("=" * 70)

        for s in sorted(sessions, key=lambda x: x.status, reverse=True):
            status_color = {
                'HEALTHY': '\033[32m',   # Green
                'WARNING': '\033[33m',   # Yellow
                'CRITICAL': '\033[31m',  # Red
            }.get(s.status, '')
            reset = '\033[0m'

            print(f"\n{status_color}[{s.status}]{reset} {s.session_id[:20]}...")
            print(f"  Size: {s.file_size_kb}KB | Tokens: ~{s.estimated_tokens:,}")
            print(f"  Context: {s.context_utilization:.0%} | Injections: {s.injection_count}")
            print(f"  Growth: {s.growth_rate_kb_per_min:.1f} KB/min")
            print(f"  → {s.recommendation}")

        print("\n" + "=" * 70)


def main():
    """CLI interface for session monitor."""
    import sys

    monitor = SessionMonitor()

    if len(sys.argv) > 1:
        cmd = sys.argv[1]

        if cmd == 'status':
            monitor.print_status()

        elif cmd == 'alerts':
            alerts = monitor.get_alerts()
            if alerts:
                for a in alerts:
                    print(f"[{a.status}] {a.session_id}: {a.recommendation}")
            else:
                print("No alerts")

        elif cmd == 'json':
            sessions = monitor.get_all_sessions()
            data = [{
                'session_id': s.session_id,
                'status': s.status,
                'size_kb': s.file_size_kb,
                'context_utilization': s.context_utilization,
                'injection_count': s.injection_count,
                'recommendation': s.recommendation,
            } for s in sessions]
            print(json.dumps(data, indent=2))

        else:
            print(f"Unknown command: {cmd}")
            print("Usage: session_monitor.py [status|alerts|json]")
            sys.exit(1)
    else:
        monitor.print_status()


if __name__ == '__main__':
    main()
