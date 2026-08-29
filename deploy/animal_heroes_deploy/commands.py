"""Allowlisted argv-only command runner with secret redaction."""

from __future__ import annotations

import os
import subprocess
from dataclasses import dataclass, field
from pathlib import Path
from typing import Mapping, Sequence

from deploy.animal_heroes_deploy.toolchain import Tool, Toolchain


class CommandPolicyError(ValueError):
    """Raised when a command violates the allowlist policy."""


@dataclass(frozen=True)
class CommandResult:
    returncode: int
    stdout: bytes
    stderr: bytes
    argv_display: tuple[str, ...]
    redacted_summary: str

    @classmethod
    def from_completed(
        cls,
        completed: subprocess.CompletedProcess[bytes],
        redactor: "Redactor",
    ) -> "CommandResult":
        argv_display = tuple(str(a) for a in completed.args)
        stdout_text = completed.stdout.decode("utf-8", errors="replace") if completed.stdout else ""
        stderr_text = completed.stderr.decode("utf-8", errors="replace") if completed.stderr else ""
        summary = f"$ {' '.join(argv_display)}\n{redactor.redact(stdout_text)}\n{redactor.redact(stderr_text)}"
        return cls(
            returncode=completed.returncode,
            stdout=completed.stdout or b"",
            stderr=completed.stderr or b"",
            argv_display=argv_display,
            redacted_summary=summary,
        )


_ALLOWED_REPO_SCRIPTS = frozenset({
    "scripts/test_all.sh",
    "game/tests/device/apk_permissions.sh",
})


class CommandRunner:
    def __init__(self, toolchain: Toolchain, repo_root: Path | None = None) -> None:
        self._toolchain = toolchain
        self._repo_root = repo_root
        self._redactor = _import_redactor()

    def run(
        self,
        tool: Tool,
        args: Sequence[str],
        *,
        cwd: Path | None = None,
        stdin: bytes | None = None,
        env_additions: Mapping[str, str] | None = None,
        secret_values: Sequence[str] = (),
        timeout_s: float = 120.0,
    ) -> CommandResult:
        executable = self._toolchain.get(tool)
        argv = (str(executable), *tuple(args))
        env = os.environ.copy()
        env.update(env_additions or {})
        redactor = self._redactor.with_values(tuple(secret_values))
        try:
            completed = subprocess.run(
                argv,
                cwd=cwd,
                input=stdin,
                env=env,
                shell=False,
                capture_output=True,
                timeout=timeout_s,
                check=False,
            )
        except subprocess.TimeoutExpired as error:
            raise TimeoutError(f"command timed out after {timeout_s}s: {tool.value}") from error
        return CommandResult.from_completed(completed, redactor)

    def run_repo_script(self, relative_path: Path) -> CommandResult:
        if self._repo_root is None:
            raise CommandPolicyError("repo_root is not configured")
        normalized = relative_path.as_posix()
        if normalized not in _ALLOWED_REPO_SCRIPTS:
            raise CommandPolicyError(f"repo script is not allowlisted: {normalized}")
        script = (self._repo_root / normalized).resolve(strict=False)
        try:
            script.relative_to(self._repo_root.resolve(strict=False))
        except ValueError:
            raise CommandPolicyError(f"repo script escapes repository root: {normalized}")
        if not script.is_file() or not os.access(script, os.X_OK):
            raise CommandPolicyError(f"repo script is not executable: {normalized}")
        try:
            completed = subprocess.run(
                (str(script),),
                cwd=self._repo_root,
                shell=False,
                capture_output=True,
                timeout=300.0,
                check=False,
            )
        except subprocess.TimeoutExpired as error:
            raise TimeoutError(f"repo script timed out: {normalized}") from error
        return CommandResult.from_completed(completed, self._redactor)

    def run_path(self, path: Path, args: Sequence[str]) -> CommandResult:
        raise CommandPolicyError("arbitrary path execution is not allowed")


def _import_redactor():
    from deploy.animal_heroes_deploy.secrets import Redactor
    return Redactor(values=())
