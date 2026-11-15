#!/usr/bin/env python3
"""Verify pinned brand copies, or import the committed HEAD of a local brand checkout."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "docs/brand/manifest.json"


def local_path(name):
    path = (ROOT / name).resolve()
    if not path.is_relative_to(ROOT) or path == ROOT:
        raise ValueError(f"Brand copy must stay inside the native checkout: {name}")
    return path


def digest(data):
    return hashlib.sha256(data).hexdigest()


def verify(manifest):
    if not re.fullmatch(r"[0-9a-f]{40}", manifest["revision"]):
        raise ValueError("The brand revision must be a full commit SHA")
    for name, entry in manifest["files"].items():
        if digest(local_path(name).read_bytes()) != entry["sha256"]:
            raise ValueError(f"Local brand copy differs from its pin: {name}")


def git(checkout, *args):
    return subprocess.check_output(["git", "-C", str(checkout), *args])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("brand_checkout", nargs="?", type=Path)
    args = parser.parse_args()
    manifest = json.loads(MANIFEST.read_text())
    verify(manifest)

    if args.brand_checkout:
        revision = git(args.brand_checkout, "rev-parse", "HEAD").decode().strip()
        if not re.fullmatch(r"[0-9a-f]{40}", revision):
            raise ValueError("The source must resolve to a full commit SHA")
        # Read every source before writing any local copy; uncommitted source edits are ignored.
        imported = {
            name: git(args.brand_checkout, "show", f"{revision}:{entry['source']}")
            for name, entry in manifest["files"].items()
        }
        for name, data in imported.items():
            path = local_path(name)
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            manifest["files"][name]["sha256"] = digest(data)
        manifest["revision"] = revision
        MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n")
        verify(manifest)

    print(f"Verified {len(manifest['files'])} brand copies at {manifest['revision']}")


if __name__ == "__main__":
    try:
        main()
    except (KeyError, OSError, ValueError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error))
