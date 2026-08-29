import os
import tempfile
import unittest
from pathlib import Path

from deploy.animal_heroes_deploy.commands import (
    CommandPolicyError,
    CommandResult,
    CommandRunner,
)
from deploy.animal_heroes_deploy.toolchain import Tool, Toolchain, ToolchainError
from deploy.tests.fake_tools import fake_runner, fake_toolchain, make_fake_executable


class CommandBoundaryTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmpdir = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmpdir.cleanup)

    def test_secret_is_child_only_and_never_rendered(self) -> None:
        runner = fake_runner(self)
        result = runner.run(
            Tool.GODOT,
            ("--headless", "--version"),
            env_additions={"GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD": "super-secret"},
            secret_values=("super-secret",),
        )
        self.assertEqual(result.returncode, 0)
        self.assertNotIn("super-secret", result.redacted_summary)
        self.assertNotIn("super-secret", " ".join(result.argv_display))

    def test_unknown_tool_and_arbitrary_bash_are_rejected(self) -> None:
        runner = fake_runner(self)
        with self.assertRaises(CommandPolicyError):
            runner.run_path(Path("/bin/sh"), ("-c", "id"))

    def test_run_repo_script_rejects_unregistered_script(self) -> None:
        runner = fake_runner(self)
        with self.assertRaises(CommandPolicyError):
            runner.run_repo_script(Path("outside.sh"))

    def test_run_repo_script_accepts_registered_script(self) -> None:
        repo_root = Path(self._tmpdir.name) / "repo"
        scripts_dir = repo_root / "scripts"
        scripts_dir.mkdir(parents=True)
        script = scripts_dir / "test_all.sh"
        script.write_text("#!/usr/bin/env bash\necho ok\n", encoding="utf-8")
        os.chmod(script, 0o755)
        runner = CommandRunner(toolchain=fake_toolchain(Path(self._tmpdir.name)), repo_root=repo_root)
        result = runner.run_repo_script(Path("scripts/test_all.sh"))
        self.assertEqual(result.returncode, 0)

    def test_stdin_is_delivered(self) -> None:
        bin_dir = Path(self._tmpdir.name) / "bin"
        make_fake_executable(bin_dir / "adb", "cat")
        resolved = {tool: bin_dir / tool.value for tool in Tool}
        runner = CommandRunner(toolchain=Toolchain(resolved=resolved))
        result = runner.run(Tool.ADB, ("pair", "127.0.0.1:1234"), stdin=b"123456\n", secret_values=("123456",))
        self.assertEqual(result.returncode, 0)
        self.assertIn("123456", result.stdout.decode("utf-8"))
        self.assertNotIn("123456", result.redacted_summary)

    def test_timeout_raises(self) -> None:
        bin_dir = Path(self._tmpdir.name) / "bin"
        make_fake_executable(bin_dir / "godot", "sleep 10")
        resolved = {tool: bin_dir / tool.value for tool in Tool}
        runner = CommandRunner(toolchain=Toolchain(resolved=resolved))
        with self.assertRaises(TimeoutError):
            runner.run(Tool.GODOT, ("--version",), timeout_s=0.5)

    def test_argv_display_shows_executable_and_args(self) -> None:
        runner = fake_runner(self)
        result = runner.run(Tool.GIT, ("status", "--porcelain"))
        self.assertIn("git", result.argv_display[0])
        self.assertIn("--porcelain", result.argv_display)


class ToolchainTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmpdir = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmpdir.cleanup)

    def test_resolve_all_from_environment(self) -> None:
        bin_dir = Path(self._tmpdir.name) / "bin"
        for tool in Tool:
            make_fake_executable(bin_dir / tool.value, "echo ok")
        env = {f"{tool.name}_BIN": str(bin_dir / tool.value) for tool in Tool}
        env["PATH"] = ""
        chain = Toolchain.resolve_all(env)
        for tool in Tool:
            self.assertEqual(chain.resolved[tool], (bin_dir / tool.value).resolve())

    def test_missing_tool_raises(self) -> None:
        with self.assertRaises(ToolchainError):
            Toolchain.resolve_all({"PATH": str(Path(self._tmpdir.name) / "nonexistent")})
