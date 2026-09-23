#!/usr/bin/env python3
"""Serve a built web probe locally with Flutter path-route fallback."""
import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse


class Handler(SimpleHTTPRequestHandler):
    def do_GET(self):
        path = Path(self.translate_path(self.path))
        if not path.exists() and not Path(urlparse(self.path).path).suffix:
            self.path = '/index.html'
        super().do_GET()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--port', type=int, default=8080)
    args = parser.parse_args()
    if not (args.directory / 'index.html').is_file():
        parser.error('The directory must contain a built Flutter web application.')
    print(f'Web probe: http://127.0.0.1:{args.port}/probe?case=default&run=<unique-id>', flush=True)
    ThreadingHTTPServer(('127.0.0.1', args.port),
                        partial(Handler, directory=str(args.directory.resolve()))).serve_forever()
