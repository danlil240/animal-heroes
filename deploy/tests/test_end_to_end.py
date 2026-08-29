"""End-to-end integration harness for the deployment system.

This test exercises the full pipeline with mocked external tools to verify
that all components work together: configuration, catalog, pipeline staging,
publication, and deployment coordination.
"""

import hashlib
import json
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import MagicMock

from deploy.animal_heroes_deploy.apk import ApkFacts, ApkInspector
from deploy.animal_heroes_deploy.audit import AuditLog
from deploy.animal_heroes_deploy.catalog import Catalog
from deploy.animal_heroes_deploy.config import DeployConfig
from deploy.animal_heroes_deploy.deployment import DeploymentCoordinator, DeploymentState
from deploy.animal_heroes_deploy.devices import AdbAdapter, DeviceProbe, InstalledPackage
from deploy.animal_heroes_deploy.domain import DeviceRole, ReleaseChannel
from deploy.animal_heroes_deploy.git_release import CheckoutSnapshot, GitReleaseOps
from deploy.animal_heroes_deploy.operation_journal import OperationJournal
from deploy.animal_heroes_deploy.paths import StatePaths
from deploy.animal_heroes_deploy.release_pipeline import (
    CandidateRequest,
    ReleasePipeline,
)
from deploy.animal_heroes_deploy.update_state import UpdatePhase, UpdateStateMachine


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


class EndToEndHarnessTests(unittest.TestCase):
    """Integration test: stage -> publish -> deploy -> verify state."""

    def setUp(self) -> None:
        self._tmpdir = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmpdir.cleanup)
        self.tmp = Path(self._tmpdir.name)
        self.paths = StatePaths.for_test(self.tmp)
        self.config = DeployConfig.from_dict(valid_config_dict(self.tmp))
        self.catalog = Catalog(self.paths)
        self.audit_log = AuditLog(self.paths)
        self.journal = OperationJournal(self.paths.runtime / "journal")

        # Mock external tools
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
        self.runner.run.return_value = MagicMock(returncode=0, stdout=b"", stderr=b"")
        self.secret_store = MagicMock()
        self.secret_store.lookup.return_value = b"keystore-password"
        self.apk_path = make_apk(self.tmp / "staged.apk")
        self.apk_inspector = MagicMock(spec=ApkInspector)
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
        self.pipeline._export_apk = lambda worktree, version_name: self.apk_path

        # Deployment mocks
        self.adb = MagicMock(spec=AdbAdapter)
        self.adb.resolve.side_effect = lambda hw: f"192.168.1.{5 if hw == 'R28M30ABCDEF' else 6}:12345"
        self.adb.probe.return_value = DeviceProbe(battery_pct=100, charging=False, free_data_bytes=500*1024*1024, device_binding_hash="x")
        self.adb.install.return_value = True
        self.adb.inspect_installed.return_value = InstalledPackage(
            package_id="org.danlil.animalheroes",
            version_code=2,
            version_name="1.0.0-rc.1",
            signer_sha256="a" * 64,
        )
        self.coordinator = DeploymentCoordinator(
            config=self.config,
            catalog=self.catalog,
            adb=self.adb,
            apk_inspector=self.apk_inspector,
            audit_log=self.audit_log,
            now_func=lambda: NOW.isoformat(),
        )

    def test_full_pipeline_stage_publish_deploy(self) -> None:
        # Stage
        staged = self.pipeline.stage_candidate(CandidateRequest("1.0.0-rc.1", "First candidate", True))
        self.assertEqual(staged.version_code, 2)
        self.assertEqual(self.catalog.list_releases(), ())

        # Publish
        record = self.pipeline.confirm_publish(staged.operation_id)
        self.assertEqual(record.version_code, 2)
        self.assertEqual(self.catalog.active().release_id, record.release_id)

        # Deploy
        result = self.coordinator.deploy_active()
        self.assertEqual(result.state, DeploymentState.COMPLETE)
        self.assertEqual(result.host_installed_version, 2)
        self.assertEqual(result.client_installed_version, 2)

        # Verify audit log
        events = self.audit_log.read()
        actions = [e["action"] for e in events]
        self.assertIn("stage_candidate", actions)
        self.assertIn("confirm_publish", actions)
        self.assertIn("deploy_active", actions)

    def test_update_state_machine_integration(self) -> None:
        sm = UpdateStateMachine()
        self.assertEqual(sm.state.phase, UpdatePhase.IDLE)

        # Simulate checking
        sm.begin_check()
        sm.report_available("1.0.0-rc.1", 2)
        self.assertTrue(sm.state.can_request_update())

        # Request and deploy
        sm.request_update()
        sm.begin_deploy()
        sm.report_complete()
        sm.reset()
        self.assertEqual(sm.state.phase, UpdatePhase.IDLE)

    def test_second_release_has_higher_version_code(self) -> None:
        # First release
        staged1 = self.pipeline.stage_candidate(CandidateRequest("1.0.0-rc.1", "First", True))
        self.pipeline.confirm_publish(staged1.operation_id)

        # Second release
        self.apk_path2 = make_apk(self.tmp / "staged2.apk", b"fake-apk-2")
        self.pipeline._export_apk = lambda worktree, version_name: self.apk_path2
        self.apk_inspector.verify.return_value = ApkFacts(
            package_id="org.danlil.animalheroes",
            version_name="1.0.0-rc.2",
            version_code=3,
            permissions=frozenset({"INTERNET", "ACCESS_NETWORK_STATE", "ACCESS_WIFI_STATE", "CHANGE_WIFI_MULTICAST_STATE"}),
            signer_sha256="a" * 64,
            apk_sha256=hashlib.sha256(b"fake-apk-2").hexdigest(),
            apk_size=len(b"fake-apk-2"),
        )
        staged2 = self.pipeline.stage_candidate(CandidateRequest("1.0.0-rc.2", "Second", True))
        self.assertEqual(staged2.version_code, 3)
        record2 = self.pipeline.confirm_publish(staged2.operation_id)
        self.assertEqual(self.catalog.active().release_id, record2.release_id)
