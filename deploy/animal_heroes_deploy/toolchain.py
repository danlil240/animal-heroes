"""Allowlisted external tool resolution."""

from __future__ import annotations

import os
import shutil
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Mapping


class Tool(str, Enum):
    GODOT = "godot"
    GIT = "git"
    ADB = "adb"
    AAPT = "aapt"
    APKSIGNER = "apksigner"
    KEYTOOL = "keytool"
    OPENSSL = "openssl"
    SECRET_TOOL = "secret-tool"


class ToolchainError(RuntimeError):
    """Raised when a required external tool cannot be resolved."""


@dataclass(frozen=True)
class Toolchain:
    resolved: dict[Tool, Path]

    @classmethod
    def resolve_all(cls, env: Mapping[str, str] | None = None) -> "Toolchain":
        env = env or dict(__import__("os").environ)
        resolved: dict[Tool, Path] = {}
        for tool in Tool:
            env_var = f"{tool.name}_BIN"
            candidate = env.get(env_var, "")
            if candidate:
                path = Path(candidate).resolve(strict=False)
                if path.is_file() and os.access(path, os.X_OK):
                    resolved[tool] = path
                    continue
            found = shutil.which(tool.value, path=env.get("PATH"))
            if found:
                resolved[tool] = Path(found).resolve(strict=False)
                continue
            raise ToolchainError(f"required tool not found: {tool.value} (set {env_var} or add to PATH)")
        return cls(resolved=resolved)

    def get(self, tool: Tool) -> Path:
        if tool not in self.resolved:
            raise ToolchainError(f"tool not resolved: {tool.value}")
        return self.resolved[tool]
