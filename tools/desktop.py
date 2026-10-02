#!/usr/bin/env python3
"""Build Windows and macOS release packages without affecting the Web workflow."""
import argparse
import os
from pathlib import Path
import platform
import shutil
import subprocess
import zipfile

from fetch_web_templates import RemoteZip

ROOT = Path(__file__).resolve().parents[1]
TEMPLATES = ROOT / ".tools" / "templates"
BUILD = ROOT / "build"
RELEASES = BUILD / "releases"
VERSION = "4.7.2"
TEMPLATE_NAMES = ("windows_release_x86_64.exe", "macos.zip")


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


def valid_template(path):
    if path.name.endswith(".zip"):
        return zipfile.is_zipfile(path)
    if not path.is_file() or path.stat().st_size < 1024 * 1024:
        return False
    with path.open("rb") as stream:
        return stream.read(2) == b"MZ"


def fetch_templates():
    TEMPLATES.mkdir(parents=True, exist_ok=True)
    wanted = [name for name in TEMPLATE_NAMES if not valid_template(TEMPLATES / name)]
    if not wanted:
        print("Desktop templates already available.", flush=True)
        return
    url = (
        f"https://github.com/godotengine/godot/releases/download/{VERSION}-stable/"
        f"Godot_v{VERSION}-stable_export_templates.tpz"
    )
    with zipfile.ZipFile(RemoteZip(url)) as archive:
        for name in wanted:
            print(f"Downloading {name}...", flush=True)
            data = archive.read(f"templates/{name}")
            destination = TEMPLATES / name
            destination.write_bytes(data)
            if not valid_template(destination):
                destination.unlink(missing_ok=True)
                raise RuntimeError(f"Downloaded template is invalid: {name}")
            print(f"Saved {len(data) / 1024 / 1024:.1f} MiB to {destination}", flush=True)


def install_macos_template(godot):
    executable = Path(godot).resolve()
    if (executable.parent / "_sc_").is_file():
        template_dir = executable.parent / "editor_data" / "export_templates" / f"{VERSION}.stable"
    elif platform.system() == "Darwin":
        template_dir = (
            Path.home()
            / "Library"
            / "Application Support"
            / "Godot"
            / "export_templates"
            / f"{VERSION}.stable"
        )
    else:
        return
    template_dir.mkdir(parents=True, exist_ok=True)
    source = TEMPLATES / "macos.zip"
    destination = template_dir / "macos.zip"
    if destination.exists() or destination.is_symlink():
        if valid_template(destination):
            return
        destination.unlink()
    try:
        destination.symlink_to(source)
    except OSError:
        shutil.copy2(source, destination)


def export():
    godot = find_godot()
    version = subprocess.check_output([godot, "--version"], text=True).strip()
    if not version.startswith(f"{VERSION}.stable"):
        raise SystemExit(f"Expected Godot {VERSION}.stable, found {version}.")
    fetch_templates()
    install_macos_template(godot)
    RELEASES.mkdir(parents=True, exist_ok=True)
    (BUILD / ".gdignore").touch()
    windows_dir = BUILD / "windows"
    shutil.rmtree(windows_dir, ignore_errors=True)
    windows_dir.mkdir(parents=True)
    subprocess.run([godot, "--headless", "--path", ROOT, "--import"], check=True)
    subprocess.run(
        [
            godot,
            "--headless",
            "--path",
            ROOT,
            "--export-release",
            "Windows",
            windows_dir / "SmoothSnake.exe",
        ],
        check=True,
    )
    windows_zip = RELEASES / "SmoothSnake-Windows-x86_64.zip"
    windows_zip.unlink(missing_ok=True)
    with zipfile.ZipFile(windows_zip, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(windows_dir.iterdir()):
            if path.is_file():
                archive.write(path, path.name)
    macos_zip = RELEASES / "SmoothSnake-macOS-universal.zip"
    macos_zip.unlink(missing_ok=True)
    subprocess.run(
        [
            godot,
            "--headless",
            "--path",
            ROOT,
            "--export-release",
            "macOS",
            macos_zip,
        ],
        check=True,
    )
    print(f"Windows package: {windows_zip}", flush=True)
    print(f"macOS package:   {macos_zip}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "action",
        choices=["build", "templates"],
        nargs="?",
        default="build",
    )
    args = parser.parse_args()
    if args.action == "templates":
        fetch_templates()
    else:
        export()


if __name__ == "__main__":
    main()
