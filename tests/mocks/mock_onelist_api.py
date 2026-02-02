#!/usr/bin/env python3
"""
Mock Onelist API server for OCTO testing.
"""

import json
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs


class MockOnelistHandler(BaseHTTPRequestHandler):
    """Handler for mock Onelist API requests."""

    def log_message(self, format, *args):
        """Suppress default logging."""
        pass

    def _send_json(self, data, status=200):
        """Send JSON response."""
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def do_GET(self):
        """Handle GET requests."""
        parsed = urlparse(self.path)
        path = parsed.path

        if path == '/health':
            self._send_json({"status": "ok", "version": "1.0.0"})
        elif path == '/api/v1/status':
            self._send_json({
                "status": "running",
                "documents": 1000,
                "collections": 5,
                "uptime_seconds": 3600
            })
        elif path == '/api/v1/collections':
            self._send_json({
                "collections": [
                    {"name": "default", "document_count": 500},
                    {"name": "code", "document_count": 300},
                    {"name": "docs", "document_count": 200}
                ]
            })
        else:
            self._send_json({"error": "Not found"}, 404)

    def do_POST(self):
        """Handle POST requests."""
        parsed = urlparse(self.path)
        path = parsed.path

        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length) if content_length else b''

        try:
            data = json.loads(body) if body else {}
        except json.JSONDecodeError:
            data = {}

        if path == '/api/v1/search':
            query = data.get('query', '')
            self._send_json({
                "query": query,
                "results": [
                    {
                        "id": "doc-001",
                        "content": f"Mock result for: {query}",
                        "score": 0.95,
                        "metadata": {"source": "test"}
                    },
                    {
                        "id": "doc-002",
                        "content": f"Another result for: {query}",
                        "score": 0.85,
                        "metadata": {"source": "test"}
                    }
                ],
                "total": 2
            })
        elif path == '/api/v1/index':
            self._send_json({
                "status": "indexed",
                "document_id": "doc-new-001"
            })
        else:
            self._send_json({"error": "Not found"}, 404)


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    server = HTTPServer(('127.0.0.1', port), MockOnelistHandler)
    print(f"Mock Onelist API running on http://127.0.0.1:{port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down mock server")
        server.shutdown()


if __name__ == '__main__':
    main()
