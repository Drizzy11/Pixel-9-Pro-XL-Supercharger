#!/usr/bin/env python3
"""Preview the static website on localhost with consistent WebP MIME types."""
import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class SiteHandler(SimpleHTTPRequestHandler):
    # Windows MIME registration can otherwise serve WebP as octet-stream,
    # downloading full-size previews instead of displaying them in the browser.
    extensions_map = {**SimpleHTTPRequestHandler.extensions_map, ".webp": "image/webp",
                      ".mjs": "text/javascript", ".js": "text/javascript",
                      ".ttf": "font/ttf", ".json": "application/json"}

    def translate_path(self, path):
        prefix = '/Supercharger_Pixel_9_Series/'
        if path.startswith(prefix):
            path = '/' + path[len(prefix):]
        return super().translate_path(path)

    def send_error(self, code, message=None, explain=None):
        page = Path(self.directory) / '404.html'
        if code == 404 and page.is_file():
            content = page.read_bytes()
            self.send_response(404)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Content-Length', str(len(content)))
            self.end_headers()
            if self.command != 'HEAD': self.wfile.write(content)
        else:
            super().send_error(code, message, explain)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    site = Path(__file__).resolve().parents[1] / "site"
    handler = partial(SiteHandler, directory=str(site))
    with ThreadingHTTPServer(("127.0.0.1", args.port), handler) as server:
        print(f"Supercharger website: http://127.0.0.1:{args.port}/", flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass


if __name__ == "__main__":
    main()
