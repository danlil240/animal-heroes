"""GNOME Keyring secret storage and secret redaction."""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Sequence

from deploy.animal_heroes_deploy.commands import CommandRunner
from deploy.animal_heroes_deploy.toolchain import Tool


class SecretError(RuntimeError):
    """Raised when a secret store operation fails."""


_SECRET_FIELD_PATTERNS = [
    re.compile(r"(?i)(password|passphrase|token|secret|api[_-]?key)\s*[=:]\s*\S+"),
    re.compile(r"(?i)(GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD)\s*=\s*\S+"),
    re.compile(r"(?i)(AH_KEYSTORE_PASSWORD)\s*=\s*\S+"),
]


@dataclass(frozen=True)
class Redactor:
    values: tuple[str, ...] = ()

    def redact(self, text: str) -> str:
        for value in self.values:
            if value:
                text = text.replace(value, "[REDACTED]")
        for pattern in _SECRET_FIELD_PATTERNS:
            text = pattern.sub(r"\1=[REDACTED]", text)
        return text

    def with_values(self, additional: Sequence[str]) -> "Redactor":
        combined = tuple(v for v in (*self.values, *additional) if v)
        return Redactor(values=combined)


_KEYRING_ATTRIBUTES = {
    "application": "animal-heroes-deploy",
}


class GnomeKeyringSecretStore:
    def __init__(self, runner: CommandRunner) -> None:
        self._runner = runner

    def store(self, key: str, value: bytes) -> None:
        attrs = {**_KEYRING_ATTRIBUTES, "key": key}
        attr_args = tuple(arg for pair in attrs.items() for arg in (pair[0], pair[1]))
        label = f"animal-heroes-deploy: {key}"
        result = self._runner.run(
            Tool.SECRET_TOOL,
            ("store", f"--label={label}", *attr_args),
            stdin=value.rstrip(b"\n") + b"\n",
            secret_values=(value.decode("utf-8", errors="replace"),),
        )
        if result.returncode != 0:
            raise SecretError(f"failed to store secret '{key}'")

    def lookup(self, key: str) -> bytes | None:
        attrs = {**_KEYRING_ATTRIBUTES, "key": key}
        attr_args = tuple(arg for pair in attrs.items() for arg in (pair[0], pair[1]))
        result = self._runner.run(
            Tool.SECRET_TOOL,
            ("lookup", *attr_args),
        )
        if result.returncode != 0 or not result.stdout.strip():
            return None
        return result.stdout.rstrip(b"\n")

    def clear(self, key: str) -> None:
        attrs = {**_KEYRING_ATTRIBUTES, "key": key}
        attr_args = tuple(arg for pair in attrs.items() for arg in (pair[0], pair[1]))
        result = self._runner.run(
            Tool.SECRET_TOOL,
            ("clear", *attr_args),
        )
        if result.returncode != 0:
            raise SecretError(f"failed to clear secret '{key}'")
