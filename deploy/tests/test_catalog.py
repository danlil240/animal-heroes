import hashlib
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from deploy.animal_heroes_deploy.catalog import (
    Catalog,
    ReleaseExistsError,
    StaleCatalogRevision,
)
from deploy.animal_heroes_deploy.domain import (
    DeploymentRecord,
    DeploymentState,
    DeviceRole,
    ReleaseChannel,
    ReleaseRecord,
)
from deploy.animal_heroes_deploy.paths import StatePaths
from deploy.animal_heroes_deploy.release_metadata import ReleaseMetadata


def release_record(
    version_name: str = "1.0.0-rc.1",
    version_code: int = 2,
    save_min: int = 1,
    save_max: int = 1,
    source_commit: str = "abc123",
) -> ReleaseRecord:
    return ReleaseRecord(
        release_id=f"{version_code:010d}-{version_name}",
        version_name=version_name,
        version_code=version_code,
        channel=ReleaseChannel.CANDIDATE,
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


def make_apk(path: Path, content: bytes = b"fake-apk") -> Path:
    path.write_bytes(content)
    return path


class CatalogTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmpdir = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmpdir.cleanup)
        self.paths = StatePaths.for_test(Path(self._tmpdir.name))
        self.catalog = Catalog(self.paths)
        self.apk = make_apk(Path(self._tmpdir.name) / "source.apk")

    def test_publish_is_immutable_and_active_is_compare_and_swap(self) -> None:
        release = release_record(version_name="1.0.0-rc.1", version_code=2)
        published = self.catalog.publish(self.apk, release)
        self.assertEqual(published.release_id, "0000000002-1.0.0-rc.1")
        self.assertEqual(self.catalog.active().release_id, published.release_id)
        with self.assertRaises(ReleaseExistsError):
            self.catalog.publish(self.apk, release)
        with self.assertRaises(StaleCatalogRevision):
            self.catalog.set_active(published.release_id, expected_revision=0)

    def test_publish_rejects_non_positive_or_non_monotonic_code(self) -> None:
        with self.assertRaises(ValueError):
            self.catalog.publish(self.apk, release_record(version_code=0))
        self.catalog.publish(self.apk, release_record(version_code=5))
        with self.assertRaises(ValueError):
            self.catalog.publish(self.apk, release_record(version_code=3))

    def test_published_apk_is_immutable(self) -> None:
        published = self.catalog.publish(self.apk, release_record(version_code=2))
        apk_path = self.catalog.apk_path(published.release_id)
        self.assertTrue(apk_path.exists())
        with self.assertRaises((PermissionError, OSError)):
            apk_path.write_bytes(b"tampered")

    def test_list_returns_releases_in_version_code_order(self) -> None:
        first = self.catalog.publish(self.apk, release_record(version_code=2))
        second = self.catalog.publish(self.apk, release_record(version_code=5))
        releases = self.catalog.list_releases()
        self.assertEqual([r.release_id for r in releases], [first.release_id, second.release_id])

    def test_get_returns_release_by_id(self) -> None:
        published = self.catalog.publish(self.apk, release_record(version_code=2))
        self.assertEqual(self.catalog.get(published.release_id).release_id, published.release_id)
        self.assertIsNone(self.catalog.get("nonexistent"))

    def test_set_active_updates_active_pointer(self) -> None:
        first = self.catalog.publish(self.apk, release_record(version_code=2))
        second = self.catalog.publish(self.apk, release_record(version_code=3))
        revision = self.catalog.revision()
        self.catalog.set_active(second.release_id, expected_revision=revision)
        self.assertEqual(self.catalog.active().release_id, second.release_id)
        self.catalog.set_active(first.release_id, expected_revision=self.catalog.revision())
        self.assertEqual(self.catalog.active().release_id, first.release_id)

    def test_append_deployment_adds_record(self) -> None:
        published = self.catalog.publish(self.apk, release_record(version_code=2))
        deployment = DeploymentRecord(
            device_role=DeviceRole.HOST,
            hardware_id="R28M30ABCDEF",
            state=DeploymentState.COMPLETE,
            version_code=2,
            started_at="2026-08-29T10:00:00Z",
            completed_at="2026-08-29T10:01:00Z",
            error=None,
        )
        self.catalog.append_deployment(published.release_id, deployment)
        updated = self.catalog.get(published.release_id)
        self.assertEqual(len(updated.deployments), 1)
        self.assertEqual(updated.deployments[0].device_role, DeviceRole.HOST)

    def test_atomic_write_preserves_previous_index_on_failure(self) -> None:
        self.catalog.publish(self.apk, release_record(version_code=2))
        original_replace = os.replace
        def fail_replace(source: object, destination: object) -> None:
            if Path(destination).name == "catalog.json":
                raise OSError("simulated catalog write failure")
            original_replace(source, destination)
        with patch(
            "deploy.animal_heroes_deploy.catalog.os.replace",
            side_effect=fail_replace,
        ), self.assertRaises(OSError):
            self.catalog.publish(self.apk, release_record(version_code=3))
        releases = self.catalog.list_releases()
        self.assertEqual(len(releases), 1)
        self.assertEqual(releases[0].version_code, 2)
