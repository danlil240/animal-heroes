import json
import os
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

from deploy.animal_heroes_deploy.audit import AuditEvent, AuditLog
from deploy.animal_heroes_deploy.paths import StatePaths


class AuditLogTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmpdir = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmpdir.cleanup)
        self.paths = StatePaths.for_test(Path(self._tmpdir.name))

    def test_append_writes_jsonl_line(self) -> None:
        log = AuditLog(self.paths)
        event = AuditEvent(
            operation_id="op-1",
            timestamp="2026-08-29T10:00:00Z",
            action="stage_candidate",
            initiator="dashboard",
            details={"version_name": "1.0.0-rc.1"},
        )
        log.append(event)
        lines = self.paths.audit_log_path.read_text(encoding="utf-8").strip().split("\n")
        self.assertEqual(len(lines), 1)
        data = json.loads(lines[0])
        self.assertEqual(data["operation_id"], "op-1")
        self.assertEqual(data["action"], "stage_candidate")

    def test_append_is_append_only(self) -> None:
        log = AuditLog(self.paths)
        for i in range(3):
            log.append(AuditEvent(
                operation_id=f"op-{i}",
                timestamp="2026-08-29T10:00:00Z",
                action="test",
                initiator="dashboard",
                details={},
            ))
        lines = self.paths.audit_log_path.read_text(encoding="utf-8").strip().split("\n")
        self.assertEqual(len(lines), 3)

    def test_redacts_secret_field_names_in_details(self) -> None:
        log = AuditLog(self.paths)
        event = AuditEvent(
            operation_id="op-1",
            timestamp="2026-08-29T10:00:00Z",
            action="sign_release",
            initiator="dashboard",
            details={"keystore_password": "super-secret", "version_name": "1.0.0"},
        )
        log.append(event)
        data = json.loads(self.paths.audit_log_path.read_text(encoding="utf-8").strip())
        self.assertEqual(data["details"]["keystore_password"], "[REDACTED]")
        self.assertEqual(data["details"]["version_name"], "1.0.0")

    def test_hardware_id_shows_only_suffix(self) -> None:
        log = AuditLog(self.paths)
        event = AuditEvent(
            operation_id="op-1",
            timestamp="2026-08-29T10:00:00Z",
            action="deploy",
            initiator="dashboard",
            details={"hardware_id": "R28M30ABCDEFGH"},
        )
        log.append(event)
        data = json.loads(self.paths.audit_log_path.read_text(encoding="utf-8").strip())
        self.assertNotIn("R28M30ABCDEFGH", str(data["details"]))
        self.assertIn("R28M30", str(data["details"]))

    def test_each_event_has_operation_uuid(self) -> None:
        log = AuditLog(self.paths)
        log.append(AuditEvent(
            operation_id="op-1",
            timestamp="2026-08-29T10:00:00Z",
            action="test",
            initiator="dashboard",
            details={},
        ))
        data = json.loads(self.paths.audit_log_path.read_text(encoding="utf-8").strip())
        self.assertIn("event_id", data)
        self.assertEqual(len(data["event_id"]), 36)  # UUID format

    def test_read_returns_all_events(self) -> None:
        log = AuditLog(self.paths)
        for i in range(3):
            log.append(AuditEvent(
                operation_id=f"op-{i}",
                timestamp="2026-08-29T10:00:00Z",
                action="test",
                initiator="dashboard",
                details={},
            ))
        events = log.read()
        self.assertEqual(len(events), 3)
        self.assertEqual(events[0]["operation_id"], "op-0")
        self.assertEqual(events[2]["operation_id"], "op-2")
