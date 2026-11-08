#!/usr/bin/env python3
"""Keep the newest two CodexNotch release versions; preview unless --apply.

Only exact versioned archive/checksum names are eligible. Backups, symlinks,
unknown files and application bundles are never traversed or removed.
"""

import argparse
import hashlib
import os
from pathlib import Path
import re
import sys


VERSION = r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
ARTIFACT = re.compile(
    rf"CodexNotch-(?P<version>{VERSION})-macOS-(?P<arch>arm64|x86_64|universal)"
    r"\.(?P<format>zip|dmg)(?P<checksum>\.sha256)?"
)


def version_key(value):
    if not re.fullmatch(VERSION, value):
        raise ValueError(f"Invalid release version: {value}")
    return tuple(map(int, value.split(".")))


def protected(path):
    return any(
        "backup" in part.casefold() or "备份" in part or part == ".git"
        for part in path.parts
    )


def scan(roots):
    artifacts = {}
    for root in roots:
        if root.is_symlink() or protected(root):
            raise ValueError(f"Refusing protected or symlink root: {root}")
        if not root.is_dir():
            raise ValueError(f"Artifact root does not exist: {root}")
        for directory, names, files in os.walk(root, followlinks=False):
            base = Path(directory)
            names[:] = [
                name for name in names
                if not protected(base / name)
                and not (base / name).is_symlink()
                and not name.endswith(".app")
                and not name.startswith(".")
            ]
            for name in files:
                match = ARTIFACT.fullmatch(name)
                path = base / name
                if match and path.is_file() and not path.is_symlink():
                    artifacts[path] = match.groupdict()
    return artifacts


def valid_checksum(path):
    checksum = path.with_name(path.name + ".sha256")
    if not checksum.is_file() or checksum.is_symlink():
        return False
    fields = checksum.read_text(encoding="utf-8").split()
    if not fields or not re.fullmatch(r"[0-9a-fA-F]{64}", fields[0]):
        return False
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest() == fields[0].lower()


def plan(roots, current_version):
    version_key(current_version)
    artifacts = scan(roots)
    packages = {path: meta for path, meta in artifacts.items() if not meta["checksum"]}
    versions = {meta["version"] for meta in packages.values()}
    if current_version not in versions:
        raise ValueError("No current release packages found; nothing will be removed")
    if max(versions, key=version_key) != current_version:
        raise ValueError("A newer release exists; refusing to prune from an older release")

    # A failed or partial build must never trigger retention. Require the pair
    # produced by release.sh in one directory and for one architecture.
    verified = False
    for path, meta in packages.items():
        if meta["version"] != current_version or meta["format"] != "zip":
            continue
        dmg = path.with_suffix(".dmg")
        if dmg in packages and valid_checksum(path) and valid_checksum(dmg):
            verified = True
            break
    if not verified:
        raise ValueError("Current ZIP/DMG and matching SHA-256 pair required; nothing will be removed")

    keep = set(sorted(versions, key=version_key, reverse=True)[:2])
    # Orphan checksums never establish a release version, and are only removed
    # when they belong to a known older package version.
    remove = sorted(
        (path for path, meta in artifacts.items()
         if meta["version"] in versions and meta["version"] not in keep),
        key=str,
    )
    return sorted(keep, key=version_key, reverse=True), remove


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--current-version", required=True)
    parser.add_argument("--apply", action="store_true", help="Delete the previewed eligible files")
    parser.add_argument("roots", nargs="+", type=Path, help="Explicit artifact directories to scan")
    args = parser.parse_args()
    try:
        # absolute() keeps symlink components visible; resolve() would hide them.
        roots = [root.expanduser().absolute() for root in args.roots]
        for root in roots:
            if any(parent.is_symlink() for parent in (root, *root.parents)):
                raise ValueError(f"Refusing root containing a symlink: {root}")
        keep, remove = plan(roots, args.current_version)
        print("Keeping release versions: " + ", ".join(keep))
        for path in remove:
            print(("Remove: " if args.apply else "Would remove: ") + str(path))
            if args.apply:
                # Recheck immediately before unlinking; never follow a new link.
                if not path.is_file() or path.is_symlink() or protected(path):
                    raise ValueError(f"Artifact changed during cleanup: {path}")
                if any(parent.is_symlink() for parent in path.parents):
                    raise ValueError(f"Artifact directory changed during cleanup: {path}")
                path.unlink()
        print(f"{'Removed' if args.apply else 'Eligible files'}: {len(remove)}")
    except (OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
