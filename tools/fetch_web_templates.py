#!/usr/bin/env python3
"""Fetch only Web templates from the official release ZIP using HTTP ranges."""
import argparse
import io
from pathlib import Path
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]


class RemoteZip(io.RawIOBase):
    def __init__(self, url):
        super().__init__()
        with urllib.request.urlopen(
            urllib.request.Request(url, method="HEAD"), timeout=30
        ) as response:
            self.url = response.url
            self.size = int(response.headers["Content-Length"])
        self.position = 0

    def seekable(self):
        return True

    def seek(self, offset, whence=0):
        self.position = offset + (0 if whence == 0 else self.position if whence == 1 else self.size)
        return self.position

    def tell(self):
        return self.position

    def read(self, count=-1):
        count = min(count if count >= 0 else self.size, self.size - self.position)
        if count <= 0:
            return b""
        end = self.position + count - 1
        request = urllib.request.Request(
            self.url, headers={"Range": f"bytes={self.position}-{end}"}
        )
        with urllib.request.urlopen(request, timeout=60) as response:
            if response.status != 206:
                raise RuntimeError("Release server does not support partial downloads.")
            data = response.read()
        if len(data) != count:
            raise RuntimeError(f"Incomplete download: expected {count}, received {len(data)}")
        self.position += len(data)
        return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", default="4.7.2")
    parser.add_argument("--output", type=Path, default=ROOT / ".tools" / "templates")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    url = (
        f"https://github.com/godotengine/godot/releases/download/{args.version}-stable/"
        f"Godot_v{args.version}-stable_export_templates.tpz"
    )
    wanted = ["web_nothreads_release.zip", "web_nothreads_debug.zip"]
    wanted = [
        name for name in wanted
        if not zipfile.is_zipfile(args.output / name)
    ]
    if not wanted:
        print("Web templates already available.", flush=True)
        return
    with zipfile.ZipFile(RemoteZip(url)) as archive:
        for name in wanted:
            destination = args.output / name
            if destination.is_file() and zipfile.is_zipfile(destination):
                print(f"Already available: {name}", flush=True)
                continue
            print(f"Downloading {name}…", flush=True)
            data = archive.read(f"templates/{name}")  # ZIP CRC verified on extraction.
            destination.write_bytes(data)
            print(f"Saved {len(data) / 1024 / 1024:.1f} MiB to {destination}", flush=True)


if __name__ == "__main__":
    main()
