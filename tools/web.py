#!/usr/bin/env python3
"""Build and serve the Godot Web export. No third-party Python packages needed."""
import argparse
import functools
import http.server
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build" / "web"


def find_godot():
    candidates = [
        os.environ.get("GODOT_BIN"),
        str(ROOT / ".tools" / "godot"),
        shutil.which("godot"),
        shutil.which("godot4"),
        "/Applications/Godot.app/Contents/MacOS/Godot",
    ]
    for candidate in candidates:
        if candidate and Path(candidate).is_file():
            return candidate
    raise SystemExit("Godot 4.7.2 not found. Set GODOT_BIN to your Godot executable.")


def build():
    godot = find_godot()
    version = subprocess.check_output([godot, "--version"], text=True).strip()
    if not version.startswith("4.7.2.stable"):
        raise SystemExit(f"Expected Godot 4.7.2.stable, found {version}. Templates must match.")
    subprocess.run([sys.executable, str(ROOT / "tools/fetch_web_templates.py")], check=True)
    BUILD.mkdir(parents=True, exist_ok=True)
    (ROOT / "build" / ".gdignore").touch()
    subprocess.run([godot, "--headless", "--path", str(ROOT), "--import"], check=True)
    subprocess.run(
        [godot, "--headless", "--path", str(ROOT), "--export-release", "Web", str(BUILD / "index.html")],
        check=True,
    )
    (BUILD / ".nojekyll").touch()
    print(f"Web build ready: {BUILD}", flush=True)


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".pck": "application/octet-stream",
        ".js": "application/javascript",
    }

    def end_headers(self):
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["build", "serve", "dev"], nargs="?", default="dev")
    parser.add_argument("--port", type=int, default=8060)
    parser.add_argument("--host", default="127.0.0.1")
    args = parser.parse_args()
    if args.action in ("build", "dev"):
        build()
    if args.action in ("serve", "dev"):
        if not (BUILD / "index.html").is_file():
            raise SystemExit("No Web build found. Run: python3 tools/web.py build")
        handler = functools.partial(Handler, directory=str(BUILD))
        with http.server.ThreadingHTTPServer((args.host, args.port), handler) as server:
            print(f"Play SmoothSnake at http://{args.host}:{args.port}", flush=True)
            try:
                server.serve_forever()
            except KeyboardInterrupt:
                pass


if __name__ == "__main__":
    main()
