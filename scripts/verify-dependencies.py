#!/usr/bin/env python3
"""Reject locally patched or differently resolved Swift packages before sign-off."""
import argparse
import json
from pathlib import Path
import subprocess
from urllib.parse import urlparse


def git(checkout, *args):
    return subprocess.check_output(["git", "-C", str(checkout), *args], text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("derived_data", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    lock = root / "shapes-app/ApproovShapes.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
    failures = []
    for pin in json.loads(lock.read_text())["pins"]:
        name = Path(urlparse(pin["location"]).path).name.removesuffix(".git")
        checkout = args.derived_data / "SourcePackages/checkouts" / name
        try:
            revision = git(checkout, "rev-parse", "HEAD")
            dirty = git(checkout, "status", "--porcelain", "--untracked-files=all")
            if revision != pin["state"]["revision"] or dirty:
                failures.append(f"{name}: checkout differs from the committed lockfile or contains local changes")
            else:
                print(f"{name}: verified {revision}")
        except (OSError, subprocess.CalledProcessError):
            failures.append(f"{name}: missing or unreadable checkout; resolve packages first")
    if failures:
        raise SystemExit("\n".join(failures))


if __name__ == "__main__":
    main()
