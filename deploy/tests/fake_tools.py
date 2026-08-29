"""Shared fake tool harness for command, secret, and audit tests."""

from __future__ import annotations

import os
import stat
import subprocess
import textwrap
from pathlib import Path
from typing import Sequence

from deploy.animal_heroes_deploy.commands import CommandResult, CommandRunner
from deploy.animal_heroes_deploy.toolchain import Tool, Toolchain


def make_fake_executable(path: Path, script: str) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("#!/usr/bin/env bash\n" + script, encoding="utf-8")
    os.chmod(path, 0o755)
    return path


def fake_toolchain(tmp: Path) -> Toolchain:
    bin_dir = tmp / "bin"
    for tool, script in [
        (Tool.GODOT, 'echo "godot 4.7.2"'),
        (Tool.GIT, 'echo "git version 2.43.0"'),
        (Tool.ADB, 'echo "Android Debug Bridge version 1.0.41"'),
        (Tool.AAPT, 'echo "Android Asset Packaging Tool (aapt)"'),
        (Tool.APKSIGNER, 'echo "apksigner"'),
        (Tool.KEYTOOL, 'echo "keytool"'),
        (Tool.OPENSSL, 'echo "OpenSSL 3.0"'),
        (Tool.SECRET_TOOL, 'echo "secret-tool"'),
    ]:
        make_fake_executable(bin_dir / tool.value, script)
    resolved = {
        Tool.GODOT: bin_dir / Tool.GODOT.value,
        Tool.GIT: bin_dir / Tool.GIT.value,
        Tool.ADB: bin_dir / Tool.ADB.value,
        Tool.AAPT: bin_dir / Tool.AAPT.value,
        Tool.APKSIGNER: bin_dir / Tool.APKSIGNER.value,
        Tool.KEYTOOL: bin_dir / Tool.KEYTOOL.value,
        Tool.OPENSSL: bin_dir / Tool.OPENSSL.value,
        Tool.SECRET_TOOL: bin_dir / Tool.SECRET_TOOL.value,
    }
    return Toolchain(resolved=resolved)


def fake_runner(test_case) -> CommandRunner:
    return CommandRunner(toolchain=fake_toolchain(Path(test_case._tmpdir.name)))
