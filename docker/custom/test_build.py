"""Offline tests for snapshot safety; no Docker daemon or media required."""

import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest


spec = importlib.util.spec_from_file_location("custom_build", Path(__file__).with_name("build.py"))
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)


class SnapshotTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        self.git("init", "-q")
        self.git("config", "user.name", "Fixture")
        self.git("config", "user.email", "fixture@localhost")
        (self.repo / "source.txt").write_text("original\n")
        (self.repo / ".gitignore").write_text("cache/\n")
        self.git("add", ".")
        self.git("commit", "-qm", "Create disposable fixture", "-m", "Used only by the offline snapshot tests.")
        self.baseline = self.git("rev-parse", "HEAD").strip()

    def tearDown(self):
        self.temp.cleanup()

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.repo), *args], text=True)

    def test_dirty_source_requires_explicit_snapshot_and_keeps_changes(self):
        (self.repo / "source.txt").write_text("changed\n")
        (self.repo / "new.txt").write_text("new\n")
        with self.assertRaisesRegex(ValueError, "Dirty source"):
            build.snapshot(self.repo, self.root / "rejected", self.baseline, False)
        metadata = build.snapshot(self.repo, self.root / "snapshot", self.baseline, True)
        self.assertTrue(metadata["dirty"])
        self.assertEqual("changed\n", (self.root / "snapshot/source.txt").read_text())
        self.assertTrue((self.root / "snapshot/new.txt").exists())
        self.assertEqual(self.baseline, self.git("rev-parse", "HEAD").strip())
        self.assertEqual("changed\n", (self.repo / "source.txt").read_text())

    def test_ignored_build_files_and_git_database_are_excluded(self):
        (self.repo / "cache").mkdir()
        (self.repo / "cache/output.txt").write_text("ignored")
        build.snapshot(self.repo, self.root / "snapshot", self.baseline, False)
        self.assertFalse((self.root / "snapshot/cache").exists())
        self.assertFalse((self.root / "snapshot/.git").exists())

    def test_hash_detects_content_changes_without_using_timestamps(self):
        metadata = build.snapshot(self.repo, self.root / "snapshot", self.baseline, False)
        source = self.root / "snapshot/source.txt"
        source.touch()
        self.assertEqual(metadata["tree_sha256"], build.tree_hash(source.parent))
        source.write_text("modified")
        self.assertNotEqual(metadata["tree_sha256"], build.tree_hash(source.parent))

    def test_modified_context_is_rejected_before_docker(self):
        output = self.root / "output"
        context = output / "context"
        context.mkdir(parents=True)
        (context / "Dockerfile").write_text("FROM scratch\n")
        (output / "manifest.json").write_text(json.dumps({"context_sha256": build.tree_hash(context)}))
        (context / "Dockerfile").write_text("FROM changed\n")
        args = type("Args", (), {"output": output})()
        with self.assertRaisesRegex(ValueError, "Build context changed"):
            build.build(args)


if __name__ == "__main__":
    unittest.main()
