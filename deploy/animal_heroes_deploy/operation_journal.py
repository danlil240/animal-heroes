"""Durable operation journal for crash-recoverable publication."""

from __future__ import annotations

import json
import os
import tempfile
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Any, Mapping


class JournalState(str, Enum):
    STAGED = "staged"
    REFS_PREFLIGHTED = "refs_preflighted"
    FAST_FORWARDED = "fast_forwarded"
    TAGGED = "tagged"
    CATALOG_PUBLISHED = "catalog_published"
    ACTIVE_SET = "active_set"
    COMPLETE = "complete"


class JournalError(RuntimeError):
    """Raised when journal operations fail."""


@dataclass(frozen=True)
class JournalEntry:
    operation_id: str
    state: JournalState
    data: Mapping[str, Any]

    def to_dict(self) -> dict[str, Any]:
        return {
            "operation_id": self.operation_id,
            "state": self.state.value,
            "data": dict(self.data),
        }

    @classmethod
    def from_dict(cls, value: Mapping[str, Any]) -> "JournalEntry":
        return cls(
            operation_id=str(value["operation_id"]),
            state=JournalState(str(value["state"])),
            data=dict(value.get("data", {})),
        )


class OperationJournal:
    def __init__(self, journal_dir: Path) -> None:
        self._dir = journal_dir
        self._dir.mkdir(parents=True, exist_ok=True)

    def _path(self, operation_id: str) -> Path:
        return self._dir / f"{operation_id}.json"

    def create(self, operation_id: str, initial_data: Mapping[str, Any]) -> JournalEntry:
        entry = JournalEntry(operation_id=operation_id, state=JournalState.STAGED, data=initial_data)
        self._write(entry)
        return entry

    def transition(self, operation_id: str, new_state: JournalState, data: Mapping[str, Any] | None = None) -> JournalEntry:
        current = self.read(operation_id)
        if data is not None:
            merged = {**current.data, **data}
        else:
            merged = current.data
        entry = JournalEntry(operation_id=operation_id, state=new_state, data=merged)
        self._write(entry)
        return entry

    def read(self, operation_id: str) -> JournalEntry:
        path = self._path(operation_id)
        if not path.exists():
            raise JournalError(f"no journal entry for operation {operation_id}")
        data = json.loads(path.read_text(encoding="utf-8"))
        return JournalEntry.from_dict(data)

    def exists(self, operation_id: str) -> bool:
        return self._path(operation_id).exists()

    def remove(self, operation_id: str) -> None:
        self._path(operation_id).unlink(missing_ok=True)

    def _write(self, entry: JournalEntry) -> None:
        path = self._path(entry.operation_id)
        content = json.dumps(entry.to_dict(), indent=2, sort_keys=True)
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", dir=self._dir, prefix=f".{entry.operation_id}.", delete=False
        ) as tmp:
            tmp.write(content)
            tmp.flush()
            os.fsync(tmp.fileno())
            tmp_path = Path(tmp.name)
        os.replace(tmp_path, path)
