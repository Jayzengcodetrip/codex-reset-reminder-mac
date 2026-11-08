#!/usr/bin/env python3
"""Retention tests use disposable synthetic files, never real release data."""

import hashlib
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from prune_release_artifacts import plan


class ReleaseRetentionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="codex-retention-test-")
        self.root = Path(self.temporary.name).resolve()

    def tearDown(self):
        self.temporary.cleanup()

    def release(self, version, directory=None):
        directory = directory or self.root
        directory.mkdir(parents=True, exist_ok=True)
        paths = []
        for extension in ("zip", "dmg"):
            path = directory / f"CodexNotch-{version}-macOS-arm64.{extension}"
            path.write_bytes(f"synthetic {version} {extension}".encode())
            path.with_name(path.name + ".sha256").write_text(
                f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path}\n"
            )
            paths.append(path)
        return paths

    def test_numeric_versions_keep_newest_two_across_explicit_roots(self):
        self.release("0.2.9")
        self.release("0.2.14")
        other = self.root / "delivery"
        self.release("0.2.15", other)
        keep, remove = plan([self.root, other], "0.2.15")
        self.assertEqual(keep, ["0.2.15", "0.2.14"])
        self.assertEqual(len(remove), 4)
        self.assertTrue(all("0.2.9" in path.name for path in remove))

    def test_backups_app_bundles_unknown_files_and_symlinks_are_protected(self):
        self.release("0.2.13")
        self.release("0.2.14")
        self.release("0.2.15")
        for directory in ("升级前备份", "Backups", "CodexNotch.app", ".git"):
            self.release("0.2.1", self.root / directory)
        unknown = self.root / "维护源码.zip"
        unknown.write_text("preserve")
        link = self.root / "CodexNotch-0.2.1-macOS-arm64.zip"
        link.symlink_to(unknown)
        keep, remove = plan([self.root], "0.2.15")
        self.assertEqual(keep, ["0.2.15", "0.2.14"])
        self.assertEqual(len(remove), 4)
        self.assertTrue(all("0.2.13" in path.name for path in remove))

    def test_partial_or_corrupt_current_release_cannot_prune(self):
        self.release("0.2.13")
        self.release("0.2.14")
        paths = self.release("0.2.15")
        paths[0].write_bytes(b"corrupt")
        with self.assertRaises(ValueError):
            plan([self.root], "0.2.15")
        paths[0].unlink()
        with self.assertRaises(ValueError):
            plan([self.root], "0.2.15")

    def test_newer_release_blocks_stale_cleanup(self):
        self.release("0.2.15")
        self.release("0.2.16")
        with self.assertRaises(ValueError):
            plan([self.root], "0.2.15")

    def test_missing_root_blocks_cleanup(self):
        self.release("0.2.15")
        with self.assertRaises(ValueError):
            plan([self.root, self.root / "missing"], "0.2.15")

    def test_orphan_checksum_does_not_count_as_previous_release(self):
        self.release("0.2.9")
        self.release("0.2.13")
        self.release("0.2.15")
        orphan = self.root / "CodexNotch-0.2.14-macOS-arm64.zip.sha256"
        orphan.write_text("incomplete")
        keep, remove = plan([self.root], "0.2.15")
        self.assertEqual(keep, ["0.2.15", "0.2.13"])
        self.assertNotIn(orphan, remove)

    def test_cli_preview_is_read_only_then_apply_removes_only_old_artifacts(self):
        old = self.release("0.2.13")
        previous = self.release("0.2.14")
        current = self.release("0.2.15")
        self.release("0.2.1", self.root / "备份")
        script = Path(__file__).with_name("prune_release_artifacts.py")
        command = [sys.executable, str(script), "--current-version", "0.2.15", str(self.root)]
        subprocess.run(command, check=True, capture_output=True)
        self.assertTrue(all(path.exists() for path in old))
        subprocess.run([*command, "--apply"], check=True, capture_output=True)
        self.assertTrue(all(not path.exists() for path in old))
        self.assertTrue(all(path.exists() for path in previous + current))
        self.assertEqual(len(list((self.root / "备份").iterdir())), 4)


if __name__ == "__main__":
    unittest.main()
