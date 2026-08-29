"""Append-only audit log with structural secret redaction."""

from __future__ import annotations

import json
import os
import re
import tempfile
import uuid
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Mapping

from deploy.animal_heroes_deploy.paths import StatePaths


_SECRET_KEY_PATTERNS = re.compile(
    r"(?i).*(password|passphrase|token|secret|api[_-]?key|private[_-]?key).*"
)
_HARDWARE_ID_PATTERN = re.compile(r"^(R28M[0-9A-Z]+)$")


@dataclass(frozen=True)
class AuditEvent:
    operation_id: str
    timestamp: str
    action: str
    initiator: str
    details: Mapping[str, Any] = field(default_factory=dict)


def _redact_details(details: Mapping[str, Any]) -> dict[str, Any]:
    redacted: dict[str, Any] = {}
    for key, value in details.items():
        if _SECRET_KEY_PATTERNS.fullmatch(key):
            redacted[key] = "[REDACTED]"
        elif key == "hardware_id" and isinstance(value, str):
            redacted[key] = _hardware_suffix(value)
        elif isinstance(value, str) and _HARDWARE_ID_PATTERN.fullmatch(value):
            redacted[key] = _hardware_suffix(value)
        elif isinstance(value, Mapping):
            redacted[key] = _redact_details(value)
        else:
            redacted[key] = value
    return redacted


def _hardware_suffix(hardware_id: str) -> str:
    if len(hardware_id) <= 6:
        return hardware_id
    return hardware_id[:6] + "***"


class AuditLog:
    def __init__(self, paths: StatePaths) -> None:
        self._path = paths.audit_log_path
        self._path.parent.mkdir(parents=True, exist_ok=True)

    def append(self, event: AuditEvent) -> None:
        record = {
            "event_id": str(uuid.uuid4()),
            "operation_id": event.operation_id,
            "timestamp": event.timestamp,
            "action": event.action,
            "initiator": event.initiator,
            "details": _redact_details(event.details),
        }
        line = json.dumps(record, sort_keys=True) + "\n"
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", dir=self._path.parent, prefix=".audit.", delete=False
        ) as tmp:
            tmp.write(line)
            tmp.flush()
            os.fsync(tmp.fileno())
            tmp_path = Path(tmp.name)
        with open(self._path, "a", encoding="utf-8") as f:
            f.write(line)
            f.flush()
            os.fsync(f.fileno())
        tmp_path.unlink(missing_ok=True)

    def read(self) -> list[dict[str, Any]]:
        if not self._path.exists():
            return []
        events: list[dict[str, Any]] = []
        for line in self._path.read_text(encoding="utf-8").splitlines():
            if line.strip():
                events.append(json.loads(line))
        return events
