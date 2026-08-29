import hashlib
import json
import os
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import MagicMock, patch

from deploy.animal_heroes_deploy.apk import ApkFacts, ApkInspector
from deploy.animal_heroes_deploy.audit import AuditLog
from deploy.animal_heroes_deploy.catalog import Catalog
from deploy.animal_heroes_deploy.config import DeployConfig
from deploy.animal_heroes_deploy.domain import DeviceIdentity, DeviceRole, ReleaseRecord
from deploy.animal_heroes_deploy.git_release import CheckoutChanged, CheckoutSnapshot, GitReleaseOps
from deploy.animal_heroes_deploy.operation_journal import OperationJournal
from deploy.animal_heroes_deploy.paths import StatePaths
from deploy.animal_heroes_deploy.release_metadata import ReleaseMetadata
from deploy.animal_heroes_deploy.release_pipeline import (
    CandidateRequest,
    ConfirmRejected,
    ReleasePipeline,
    StageRejected,
    StagedRelease,
)
from deploy.animal_heroes_deploy.secrets import GnomeKeyringSecretStore


NOW = datetime(2026, 8, 29, 10, 0, 0, tzinfo=timezone.utc)


def valid_config_dict(tmp: Path) -> dict[str, object]:
    keystore = tmp / "release.keystore"
    keystore.write_bytes(b"dummy")
    return {
        "package_id": "org.danlil.animalheroes",
        "lan_address": "192.168.1.100",
        "lan_port": 8443,
        "dashboard_port": 8442,
        "discovery_port": 28742,
        "keystore_path": str(keystore),
        "keystore_alias": "animalheroes",
        "pinned_signer_sha256": "a" * 64,
        "devices": [
            {"role": "host", "hardware_id": "R28M30ABCDEF"},
            {"role": "client", "hardware_id": "R28M30GHIJKL"},
        ],
        "retention": "retain_all",
    }


def make_apk(path: Path, content: bytes = b"fake-apk") -> Path:
    path.write_bytes(content)
    return path


class CandidatePipelineTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmpdir = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmpdir.cleanup)
        self.tmp = Path(self._tmpdir.name)
        self.paths = StatePaths.for_test(self.tmp)
        self.config = DeployConfig.from_dict(valid_config_dict(self.tmp))
        self.catalog = Catalog(self.paths)
        self.journal = OperationJournal(self.paths.runtime / "journal")
        self.audit_log = AuditLog(self.paths)
        self.runner = MagicMock()
        self.git_ops = MagicMock()
        self.git_ops.snapshot.return_value = CheckoutSnapshot(
            head_sha="abc123",
            branch="codex/release-candidate-stabilization",
            remote_url="git@github.com:user/repo.git",
            is_clean=True,
        )
        self.git_ops.verify_clean.return_value = CheckoutSnapshot(
            head_sha="abc123",
            branch="codex/release-candidate-stabilization",
            remote_url="git@github.com:user/repo.git",
            is_clean=True,
        )
        # Create repo_root metadata for source_metadata loading
        (self.tmp / "release").mkdir(parents=True, exist_ok=True)
        (self.tmp / "release/metadata.json").write_text(
            json.dumps({
                "version_name": "1.0.0-dev.1",
                "version_code": 1,
                "application_protocol_version": 1,
                "save_schema_version": 1,
                "save_schema_compatible_min": 1,
                "save_schema_compatible_max": 1,
            }),
            encoding="utf-8",
        )
        self.git_ops.ref_exists.return_value = False
        self.git_ops.create_worktree.return_value = self.tmp / "worktree"
        (self.tmp / "worktree").mkdir(exist_ok=True)
        (self.tmp / "worktree" / "release").mkdir(parents=True, exist_ok=True)
        (self.tmp / "worktree" / "release/metadata.json").write_text(
            json.dumps({
                "version_name": "1.0.0-dev.1",
                "version_code": 1,
                "application_protocol_version": 1,
                "save_schema_version": 1,
                "save_schema_compatible_min": 1,
                "save_schema_compatible_max": 1,
            }),
            encoding="utf-8",
        )
        (self.tmp / "worktree" / "game").mkdir(parents=True, exist_ok=True)
        (self.tmp / "worktree" / "game/export_presets.cfg").write_text(
            "version/code=1\nversion/name=\"1.0.0-dev.1\"\n", encoding="utf-8"
        )
        self.git_ops.commit_all.return_value = "def456"
        self.runner.run_repo_script.return_value = MagicMock(returncode=0, stdout=b"PASS\n", stderr=b"")
        self.secret_store = MagicMock()
        self.secret_store.lookup.return_value = b"keystore-password"
        apk_path = make_apk(self.tmp / "staged.apk")
        self.runner.run.return_value = MagicMock(returncode=0, stdout=b"", stderr=b"")
        self.apk_inspector = MagicMock()
        self.apk_inspector.verify.return_value = ApkFacts(
            package_id="org.danlil.animalheroes",
            version_name="1.0.0-rc.1",
            version_code=2,
            permissions=frozenset({"INTERNET", "ACCESS_NETWORK_STATE", "ACCESS_WIFI_STATE", "CHANGE_WIFI_MULTICAST_STATE"}),
            signer_sha256="a" * 64,
            apk_sha256=hashlib.sha256(b"fake-apk").hexdigest(),
            apk_size=len(b"fake-apk"),
        )
        self.pipeline = ReleasePipeline(
            config=self.config,
            catalog=self.catalog,
            runner=self.runner,
            git_ops=self.git_ops,
            apk_inspector=self.apk_inspector,
            secret_store=self.secret_store,
            audit_log=self.audit_log,
            journal=self.journal,
            repo_root=self.tmp,
            now=NOW,
        )
        # Patch the _export_apk to return our fake APK
        self.pipeline._export_apk = lambda worktree, version_name: apk_path

    def test_stage_does_not_change_refs_catalog_or_active(self) -> None:
        before_releases = self.catalog.list_releases()
        before_active = self.catalog.active()
        staged = self.pipeline.stage_candidate(CandidateRequest("1.0.0-rc.1", "First managed candidate", True))
        self.assertEqual(staged.version_code, 2)
        self.assertEqual(self.catalog.list_releases(), before_releases)
        self.assertEqual(self.catalog.active(), before_active)

    def test_confirm_refuses_changed_checkout(self) -> None:
        staged = self.pipeline.stage_candidate(CandidateRequest("1.0.0-rc.1", "Candidate", False))
        self.git_ops.snapshot.return_value = CheckoutSnapshot(
            head_sha="changed",
            branch="codex/release-candidate-stabilization",
            remote_url="git@github.com:user/repo.git",
            is_clean=True,
        )
        with self.assertRaises(CheckoutChanged):
            self.pipeline.confirm_publish(staged.operation_id)
        self.assertEqual(self.catalog.list_releases(), ())

    def test_confirm_publishes_and_activates(self) -> None:
        staged = self.pipeline.stage_candidate(CandidateRequest("1.0.0-rc.1", "Candidate", True))
        record = self.pipeline.confirm_publish(staged.operation_id)
        self.assertEqual(record.version_code, 2)
        self.assertEqual(self.catalog.active().release_id, record.release_id)
        self.assertFalse(self.journal.exists(staged.operation_id))

    def test_confirm_without_activate(self) -> None:
        staged = self.pipeline.stage_candidate(CandidateRequest("1.0.0-rc.1", "Candidate", False))
        record = self.pipeline.confirm_publish(staged.operation_id)
        self.assertEqual(record.version_code, 2)
        self.assertIsNotNone(self.catalog.get(record.release_id))
        # First published release auto-activates
        self.assertEqual(self.catalog.active().release_id, record.release_id)

    def test_stage_rejects_existing_tag(self) -> None:
        self.git_ops.ref_exists.return_value = True
        with self.assertRaises(StageRejected):
            self.pipeline.stage_candidate(CandidateRequest("1.0.0-rc.1", "Candidate", False))

    def test_stage_rejects_dirty_checkout(self) -> None:
        from deploy.animal_heroes_deploy.git_release import DirtyCheckout
        self.git_ops.verify_clean.side_effect = DirtyCheckout("dirty")
        with self.assertRaises(StageRejected):
            self.pipeline.stage_candidate(CandidateRequest("1.0.0-rc.1", "Candidate", False))

    def test_stage_rejects_failed_tests(self) -> None:
        self.runner.run_repo_script.return_value = MagicMock(returncode=1, stdout=b"FAIL\n", stderr=b"")
        with self.assertRaises(StageRejected):
            self.pipeline.stage_candidate(CandidateRequest("1.0.0-rc.1", "Candidate", False))

    def test_stage_computes_next_version_code(self) -> None:
        staged1 = self.pipeline.stage_candidate(CandidateRequest("1.0.0-rc.1", "First", True))
        self.pipeline._export_apk = lambda worktree, version_name: make_apk(self.tmp / "staged2.apk", b"apk2")
        self.pipeline.confirm_publish(staged1.operation_id)
        staged2 = self.pipeline.stage_candidate(CandidateRequest("1.0.0-rc.2", "Second", False))
        self.assertEqual(staged2.version_code, 3)
