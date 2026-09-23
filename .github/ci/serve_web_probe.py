#!/usr/bin/env python3
"""Serve a built web probe locally with Flutter path-route fallback."""
import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import os
from pathlib import Path
from urllib.parse import urlparse


class Handler(SimpleHTTPRequestHandler):
    extensions_map = {**SimpleHTTPRequestHandler.extensions_map, '.wasm': 'application/wasm'}

    def translate_path(self, path):
        fixture = urlparse(path).path
        if fixture in ('/__restart_probe__/before.html', '/__restart_probe__/parent.html'):
            return str(Path(__file__).with_name('web-fixtures') / Path(fixture).name)
        return super().translate_path(path)

    def end_headers(self):
        # Opaque sandbox frames fetch the same test assets with Origin: null.
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()

    def log_request(self, code='-', size='-'):
        if code != '-' and int(code) >= 400:
            super().log_request(code, size)

    def do_GET(self):
        path = Path(self.translate_path(self.path))
        if not path.exists() and not Path(urlparse(self.path).path).suffix:
            self.path = '/index.html'
        super().do_GET()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path, nargs='?',
                        default=os.environ.get('RESTART_WEB_BUILD'))
    parser.add_argument('--port', type=int,
                        default=int(os.environ.get('RESTART_WEB_PORT', '8080')))
    args = parser.parse_args()
    if args.directory is None or not (args.directory / 'index.html').is_file():
        parser.error('The directory must contain a built Flutter web application.')
    print(f'Web probe: http://127.0.0.1:{args.port}/probe?case=default&run=<unique-id>', flush=True)
    ThreadingHTTPServer(('127.0.0.1', args.port),
                        partial(Handler, directory=str(args.directory.resolve()))).serve_forever()
