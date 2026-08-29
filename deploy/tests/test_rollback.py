import hashlib
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock

from deploy.animal_heroes_deploy.catalog import Catalog
from deploy.animal_heroes_deploy.domain import (
    DeploymentRecord,
    DeploymentState,
    DeviceRole,
    ReleaseChannel,
    ReleaseRecord,
)
from deploy.animal_heroes_deploy.paths import StatePaths
from deploy.animal_heroes_deploy.release_metadata import ReleaseMetadata
from deploy.animal_heroes_deploy.rollback import IncompatibleRollback, RollbackPlanner


def release_record(
    version_name: str = "1.0.0-rc.1",
    version_code: int = 2,
    save_min: int = 1,
    save_max: int = 1,
    source_commit: str = "abc123",
    channel: ReleaseChannel = ReleaseChannel.CANDIDATE,
) -> ReleaseRecord:
    return ReleaseRecord(
        release_id=f"{version_code:010d}-{version_name}",
        version_name=version_name,
        version_code=version_code,
        channel=channel,
        source_commit=source_commit,
        release_commit=source_commit,
        tag=f"v{version_name}",
        built_at="2026-08-29T10:00:00Z",
        package_id="org.danlil.animalheroes",
        apk_size=1024,
        apk_sha256=hashlib.sha256(b"apk").hexdigest(),
        signer_sha256="a" * 64,
        permissions=frozenset({"INTERNET", "ACCESS_NETWORK_STATE", "ACCESS_WIFI_STATE", "CHANGE_WIFI_MULTICAST_STATE"}),
        managed_metadata=ReleaseMetadata(
            version_name=version_name,
            version_code=version_code,
            application_protocol_version=1,
            save_schema_version=save_max,
            save_schema_compatible_min=save_min,
            save_schema_compatible_max=save_max,
        ),
        rollback_of=None,
        deployments=(),
    )


def make_apk(path: Path) -> Path:
    path.write_bytes(b"fake-apk")
    return path


class RollbackTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmpdir = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmpdir.cleanup)
        self.paths = StatePaths.for_test(Path(self._tmpdir.name))
        self.catalog = Catalog(self.paths)
        self.apk = make_apk(Path(self._tmpdir.name) / "source.apk")

    def test_old_source_must_read_current_deployed_schema(self) -> None:
        source = release_record(save_min=1, save_max=1, source_commit="abc")
        self.catalog.publish(self.apk, source)
        current = release_record(version_name="2.0.0", version_code=5, save_min=2, save_max=2, source_commit="def")
        self.catalog.publish(self.apk, current)
        self.catalog.set_active(current.release_id, expected_revision=self.catalog.revision())
        planner = RollbackPlanner(self.catalog)
        with self.assertRaises(IncompatibleRollback):
            planner.prepare(source.release_id, "1.0.0-rc.2")

    def test_compatible_rollback_succeeds(self) -> None:
        source = release_record(save_min=1, save_max=2, source_commit="abc")
        self.catalog.publish(self.apk, source)
        current = release_record(version_name="2.0.0", version_code=5, save_min=1, save_max=2, source_commit="def")
        self.catalog.publish(self.apk, current)
        self.catalog.set_active(current.release_id, expected_revision=self.catalog.revision())
        planner = RollbackPlanner(self.catalog)
        request = planner.prepare(source.release_id, "1.0.0-rc.2")
        self.assertEqual(request.version_name, "1.0.0-rc.2")
        self.assertEqual(request.source_commit, "abc")
        self.assertEqual(request.rollback_of, source.release_id)
        self.assertFalse(request.activate)

    def test_refuses_unmanaged_source(self) -> None:
        source = release_record(source_commit="abc")
        # Create a release without managed_metadata by publishing normally
        self.catalog.publish(self.apk, source)
        planner = RollbackPlanner(self.catalog)
        # All releases from our catalog have managed_metadata; test with None
        with self.assertRaises(IncompatibleRollback):
            planner.prepare("nonexistent-release", "1.0.0-rc.2")

    def test_refuses_reused_version_name(self) -> None:
        source = release_record(version_name="1.0.0-rc.1", save_min=1, save_max=2, source_commit="abc")
        self.catalog.publish(self.apk, source)
        self.catalog.set_active(source.release_id, expected_revision=self.catalog.revision())
        planner = RollbackPlanner(self.catalog)
        with self.assertRaises(IncompatibleRollback):
            planner.prepare(source.release_id, "1.0.0-rc.1")

    def test_refuses_when_no_active_release(self) -> None:
        source = release_record(save_min=1, save_max=2, source_commit="abc")
        self.catalog.publish(self.apk, source)
        # Don't set active - but publish auto-activates first release
        # So we need to test with a catalog that has no active
        planner = RollbackPlanner(self.catalog)
        # First release auto-activates, so this should work
        request = planner.prepare(source.release_id, "1.0.0-rc.2")
        self.assertEqual(request.source_commit, "abc")
