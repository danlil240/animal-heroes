"""Git release operations: isolated worktree, branch, commit, tag, fast-forward."""

from __future__ import annotations

import subprocess
from dataclasses import dataclass
from pathlib import Path

from deploy.animal_heroes_deploy.commands import CommandRunner, CommandPolicyError
from deploy.animal_heroes_deploy.toolchain import Tool


class GitReleaseError(RuntimeError):
    """Raised when a Git release operation fails."""


class DirtyCheckout(GitReleaseError):
    """Raised when the working tree is not clean."""


class WrongRepository(GitReleaseError):
    """Raised when the checkout is not the expected repository/branch."""


class CheckoutChanged(GitReleaseError):
    """Raised when the original checkout changed during staging."""


class NonFastForward(GitReleaseError):
    """Raised when a fast-forward is not possible."""


@dataclass(frozen=True)
class CheckoutSnapshot:
    head_sha: str
    branch: str
    remote_url: str
    is_clean: bool


class GitReleaseOps:
    def __init__(self, runner: CommandRunner, repo_root: Path) -> None:
        self._runner = runner
        self._repo_root = repo_root

    def snapshot(self) -> CheckoutSnapshot:
        head = self._git("rev-parse", "HEAD").strip()
        branch = self._git("rev-parse", "--abbrev-ref", "HEAD").strip()
        url = self._git("remote", "get-url", "origin").strip()
        is_clean = self._git("status", "--porcelain=v1", "--untracked-files=all").strip() == ""
        return CheckoutSnapshot(head_sha=head, branch=branch, remote_url=url, is_clean=is_clean)

    def verify_clean(self, expected_branch: str, expected_remote: str) -> CheckoutSnapshot:
        snap = self.snapshot()
        if not snap.is_clean:
            raise DirtyCheckout("working tree has uncommitted or untracked changes")
        if snap.branch != expected_branch:
            raise WrongRepository(f"expected branch '{expected_branch}', got '{snap.branch}'")
        if snap.remote_url != expected_remote:
            raise WrongRepository(f"expected remote '{expected_remote}', got '{snap.remote_url}'")
        return snap

    def create_worktree(self, source_commit: str, branch_name: str) -> Path:
        import tempfile
        worktree_path = Path(tempfile.mkdtemp(prefix="ah-release-"))
        result = self._runner.run(
            Tool.GIT,
            ("worktree", "add", str(worktree_path), "-b", branch_name, source_commit),
            cwd=self._repo_root,
        )
        if result.returncode != 0:
            raise GitReleaseError(f"git worktree add failed: {result.redacted_summary}")
        return worktree_path

    def remove_worktree(self, worktree_path: Path) -> None:
        result = self._runner.run(
            Tool.GIT,
            ("worktree", "remove", str(worktree_path), "--force"),
            cwd=self._repo_root,
        )
        if result.returncode != 0:
            import shutil
            shutil.rmtree(worktree_path, ignore_errors=True)

    def commit_all(self, worktree: Path, message: str) -> str:
        self._git_in(worktree, "add", "-A")
        result = self._git_in(worktree, "commit", "-m", message)
        if result.returncode != 0:
            raise GitReleaseError(f"git commit failed: {result.redacted_summary}")
        return self._git_in(worktree, "rev-parse", "HEAD").strip()

    def create_tag(self, repo_root: Path, tag: str, commit_sha: str) -> None:
        result = self._runner.run(
            Tool.GIT,
            ("tag", "-a", tag, commit_sha, "-m", f"Release {tag}"),
            cwd=repo_root,
        )
        if result.returncode != 0:
            raise GitReleaseError(f"git tag failed: {result.redacted_summary}")

    def fast_forward(self, branch: str, commit_sha: str) -> None:
        current = self._git("rev-parse", branch).strip()
        result = self._runner.run(
            Tool.GIT,
            ("merge-base", "--is-ancestor", current, commit_sha),
            cwd=self._repo_root,
        )
        if result.returncode != 0:
            raise NonFastForward(f"{commit_sha} is not a descendant of {branch}")
        self._git("update-ref", f"refs/heads/{branch}", commit_sha, current)

    def ref_exists(self, ref: str) -> bool:
        result = self._runner.run(Tool.GIT, ("rev-parse", "--verify", ref), cwd=self._repo_root)
        return result.returncode == 0

    def _git(self, *args: str) -> str:
        return self._git_in(self._repo_root, *args)

    def _git_in(self, cwd: Path, *args: str) -> str:
        result = self._runner.run(Tool.GIT, args, cwd=cwd)
        if result.returncode != 0:
            raise GitReleaseError(f"git {' '.join(args)} failed: {result.redacted_summary}")
        return result.stdout.decode("utf-8", errors="replace")
