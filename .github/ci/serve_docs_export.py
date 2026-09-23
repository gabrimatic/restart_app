#!/usr/bin/env python3
"""Serve the built Pages artifact under the package's repository prefix."""
import http.server
import os
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(os.environ["RESTART_DOCS_SITE"]).resolve(strict=True)
PREFIX = "/restart_app"


class Handler(http.server.SimpleHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def do_GET(self):
        path = urlsplit(self.path).path
        if not (path == PREFIX or path.startswith(PREFIX + "/")):
            self.send_error(404)
            return
        super().do_GET()

    def translate_path(self, path):
        # Keep self.path intact so directory redirects retain the Pages prefix.
        return super().translate_path(path[len(PREFIX):] or "/")

    def log_request(self, code="-", size="-"):
        if code != "-" and int(code) >= 400:
            super().log_request(code, size)


class Server(http.server.ThreadingHTTPServer):
    request_queue_size = 64


if __name__ == "__main__":
    Server(
        ("127.0.0.1", int(os.environ.get("RESTART_DOCS_PORT", "8768"))), Handler
    ).serve_forever()
