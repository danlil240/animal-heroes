import unittest
from pathlib import Path

from deploy.animal_heroes_deploy.git_release import (
    CheckoutSnapshot,
    DirtyCheckout,
    GitReleaseOps,
    WrongRepository,
)
from deploy.animal_heroes_deploy.toolchain import Tool
from unittest.mock import MagicMock


class GitReleaseOpsTests(unittest.TestCase):
    def test_snapshot_parses_clean_tree(self) -> None:
        runner = MagicMock()
        responses = {
            ("rev-parse", "HEAD"): "abc123\n",
            ("rev-parse", "--abbrev-ref", "HEAD"): "main\n",
            ("remote", "get-url", "origin"): "git@github.com:user/repo.git\n",
            ("status", "--porcelain=v1", "--untracked-files=all"): "",
        }
        def run_fn(tool, args, **kwargs):
            key = tuple(args)
            return MagicMock(returncode=0, stdout=responses.get(key, b"").encode() if isinstance(responses.get(key, ""), str) else responses.get(key, b""), stderr=b"")
        runner.run.side_effect = run_fn
        ops = GitReleaseOps(runner, Path("/repo"))
        snap = ops.snapshot()
        self.assertEqual(snap.head_sha, "abc123")
        self.assertEqual(snap.branch, "main")
        self.assertTrue(snap.is_clean)

    def test_verify_clean_rejects_dirty(self) -> None:
        runner = MagicMock()
        responses = {
            ("rev-parse", "HEAD"): "abc123\n",
            ("rev-parse", "--abbrev-ref", "HEAD"): "main\n",
            ("remote", "get-url", "origin"): "git@github.com:user/repo.git\n",
            ("status", "--porcelain=v1", "--untracked-files=all"): " M file.txt\n",
        }
        def run_fn(tool, args, **kwargs):
            key = tuple(args)
            return MagicMock(returncode=0, stdout=responses.get(key, b"").encode() if isinstance(responses.get(key, ""), str) else responses.get(key, b""), stderr=b"")
        runner.run.side_effect = run_fn
        ops = GitReleaseOps(runner, Path("/repo"))
        with self.assertRaises(DirtyCheckout):
            ops.verify_clean("main", "git@github.com:user/repo.git")

    def test_verify_clean_rejects_wrong_branch(self) -> None:
        runner = MagicMock()
        responses = {
            ("rev-parse", "HEAD"): "abc123\n",
            ("rev-parse", "--abbrev-ref", "HEAD"): "wrong\n",
            ("remote", "get-url", "origin"): "git@github.com:user/repo.git\n",
            ("status", "--porcelain=v1", "--untracked-files=all"): "",
        }
        def run_fn(tool, args, **kwargs):
            key = tuple(args)
            return MagicMock(returncode=0, stdout=responses.get(key, b"").encode() if isinstance(responses.get(key, ""), str) else responses.get(key, b""), stderr=b"")
        runner.run.side_effect = run_fn
        ops = GitReleaseOps(runner, Path("/repo"))
        with self.assertRaises(WrongRepository):
            ops.verify_clean("main", "git@github.com:user/repo.git")

    def test_ref_exists(self) -> None:
        runner = MagicMock()
        runner.run.return_value = MagicMock(returncode=0, stdout=b"abc123\n", stderr=b"")
        ops = GitReleaseOps(runner, Path("/repo"))
        self.assertTrue(ops.ref_exists("refs/tags/v1.0.0"))
        runner.run.return_value = MagicMock(returncode=1, stdout=b"", stderr=b"")
        self.assertFalse(ops.ref_exists("refs/tags/v2.0.0"))
