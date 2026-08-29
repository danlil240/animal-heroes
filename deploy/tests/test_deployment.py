import hashlib
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import MagicMock

from deploy.animal_heroes_deploy.apk import ApkFacts, ApkInspector
from deploy.animal_heroes_deploy.audit import AuditLog
from deploy.animal_heroes_deploy.catalog import Catalog
from deploy.animal_heroes_deploy.config import DeployConfig
from deploy.animal_heroes_deploy.deployment import (
    DeploymentCoordinator,
    DeploymentError,
    DeploymentResult,
    DeploymentState,
    PreflightFailed,
)
from deploy.animal_heroes_deploy.devices import (
    AdbAdapter,
    DeviceProbe,
    InstalledPackage,
    TransportError,
)
from deploy.animal_heroes_deploy.domain import DeviceIdentity, DeviceRole, ReleaseChannel, ReleaseRecord
from deploy.animal_heroes_deploy.paths import StatePaths
from deploy.animal_heroes_deploy.release_metadata import ReleaseMetadata


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


def make_release(version_code: int = 2, signer: str = "a" * 64) -> ReleaseRecord:
    return ReleaseRecord(
        release_id=f"{version_code:010d}-1.0.0-rc.1",
        version_name="1.0.0-rc.1",
        version_code=version_code,
        channel=ReleaseChannel.CANDIDATE,
        source_commit="abc123",
        release_commit="abc123",
        tag="v1.0.0-rc.1",
        built_at=NOW.isoformat(),
        package_id="org.danlil.animalheroes",
        apk_size=1024,
        apk_sha256=hashlib.sha256(b"apk").hexdigest(),
        signer_sha256=signer,
        permissions=frozenset({"INTERNET", "ACCESS_NETWORK_STATE", "ACCESS_WIFI_STATE", "CHANGE_WIFI_MULTICAST_STATE"}),
        managed_metadata=ReleaseMetadata(
            version_name="1.0.0-rc.1",
            version_code=version_code,
            application_protocol_version=1,
            save_schema_version=1,
            save_schema_compatible_min=1,
            save_schema_compatible_max=1,
        ),
        rollback_of=None,
        deployments=(),
    )


def make_apk(path: Path) -> Path:
    path.write_bytes(b"fake-apk-content")
    return path


class DeploymentCoordinatorTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmpdir = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmpdir.cleanup)
        self.tmp = Path(self._tmpdir.name)
        self.paths = StatePaths.for_test(self.tmp)
        self.config = DeployConfig.from_dict(valid_config_dict(self.tmp))
        self.catalog = Catalog(self.paths)
        self.audit_log = AuditLog(self.paths)
        self.adb = MagicMock(spec=AdbAdapter)
        self.apk_inspector = MagicMock(spec=ApkInspector)
        self.coordinator = DeploymentCoordinator(
            config=self.config,
            catalog=self.catalog,
            adb=self.adb,
            apk_inspector=self.apk_inspector,
            audit_log=self.audit_log,
            now_func=lambda: NOW.isoformat(),
        )
        self.apk = make_apk(self.tmp / "release.apk")
        self.release = make_release()
        self.catalog.publish(self.apk, self.release)
        self.catalog.set_active(self.release.release_id, expected_revision=self.catalog.revision())

    def _setup_healthy_devices(self) -> None:
        self.adb.resolve.side_effect = lambda hw: f"192.168.1.{5 if hw == 'R28M30ABCDEF' else 6}:12345"
        self.adb.probe.return_value = DeviceProbe(battery_pct=100, charging=False, free_data_bytes=500*1024*1024, device_binding_hash="x")
        self.adb.install.return_value = True
        self.adb.inspect_installed.return_value = InstalledPackage(
            package_id="org.danlil.animalheroes",
            version_code=2,
            version_name="1.0.0-rc.1",
            signer_sha256="a" * 64,
        )

    def test_complete_when_both_installations_succeed(self) -> None:
        self._setup_healthy_devices()
        result = self.coordinator.deploy_active()
        self.assertEqual(result.state, DeploymentState.COMPLETE)
        self.assertEqual(result.host_installed_version, 2)
        self.assertEqual(result.client_installed_version, 2)
        # Host installed before client (deterministic order)
        install_calls = self.adb.install.call_args_list
        self.assertEqual(install_calls[0].args[0], "192.168.1.5:12345")
        self.assertEqual(install_calls[1].args[0], "192.168.1.6:12345")

    def test_failed_when_no_active_release(self) -> None:
        # Create a fresh catalog with no active
        fresh_tmp = tempfile.TemporaryDirectory()
        self.addCleanup(fresh_tmp.cleanup)
        fresh_paths = StatePaths.for_test(Path(fresh_tmp.name))
        fresh_catalog = Catalog(fresh_paths)
        coordinator = DeploymentCoordinator(
            config=self.config,
            catalog=fresh_catalog,
            adb=self.adb,
            apk_inspector=self.apk_inspector,
            audit_log=self.audit_log,
        )
        with self.assertRaises(PreflightFailed):
            coordinator.deploy_active()

    def test_version_split_when_one_device_fails(self) -> None:
        self._setup_healthy_devices()
        # Client install fails
        def install_fn(endpoint, apk_path):
            return False if "192.168.1.6" in endpoint else True
        self.adb.install.side_effect = install_fn
        # Host verifies, client doesn't
        def inspect_fn(endpoint, package_id, inspector):
            if "192.168.1.6" in endpoint:
                raise RuntimeError("not installed")
            return InstalledPackage(package_id="org.danlil.animalheroes", version_code=2, version_name="1.0.0-rc.1", signer_sha256="a"*64)
        self.adb.inspect_installed.side_effect = inspect_fn
        result = self.coordinator.deploy_active()
        self.assertEqual(result.state, DeploymentState.VERSION_SPLIT)
        self.assertEqual(result.host_installed_version, 2)
        self.assertIsNone(result.client_installed_version)

    def test_retry_only_failed_device_after_split(self) -> None:
        self._setup_healthy_devices()
        previous = DeploymentResult(
            state=DeploymentState.VERSION_SPLIT,
            host_installed_version=2,
            client_installed_version=None,
            host_endpoint="192.168.1.5:12345",
            client_endpoint="192.168.1.6:12345",
        )
        self.adb.install.return_value = True
        self.adb.inspect_installed.return_value = InstalledPackage(
            package_id="org.danlil.animalheroes",
            version_code=2,
            version_name="1.0.0-rc.1",
            signer_sha256="a" * 64,
        )
        result = self.coordinator.retry_failed_device(previous)
        self.assertEqual(result.state, DeploymentState.COMPLETE)
        # Only client should be installed
        install_calls = self.adb.install.call_args_list
        self.assertEqual(len(install_calls), 1)
        self.assertEqual(install_calls[0].args[0], "192.168.1.6:12345")

    def test_retry_rejects_non_split(self) -> None:
        previous = DeploymentResult(
            state=DeploymentState.COMPLETE,
            host_installed_version=2,
            client_installed_version=2,
            host_endpoint="192.168.1.5:12345",
            client_endpoint="192.168.1.6:12345",
        )
        with self.assertRaises(DeploymentError):
            self.coordinator.retry_failed_device(previous)

    def test_transport_error_retries_once(self) -> None:
        self._setup_healthy_devices()
        call_count = {"n": 0}
        def install_fn(endpoint, apk_path):
            if "192.168.1.5" in endpoint:
                call_count["n"] += 1
                if call_count["n"] == 1:
                    raise TransportError("transient")
                return True
            return True
        self.adb.install.side_effect = install_fn
        result = self.coordinator.deploy_active()
        self.assertEqual(result.state, DeploymentState.COMPLETE)

    def test_transport_error_does_not_retry_twice(self) -> None:
        self._setup_healthy_devices()
        self.adb.install.side_effect = TransportError("persistent")
        result = self.coordinator.deploy_active()
        self.assertEqual(result.state, DeploymentState.FAILED)

    def test_preflight_rejects_unresolved_device(self) -> None:
        self.adb.resolve.return_value = None
        with self.assertRaises(PreflightFailed):
            self.coordinator.deploy_active()

    def test_preflight_rejects_low_battery(self) -> None:
        self.adb.resolve.side_effect = lambda hw: f"192.168.1.{5 if hw == 'R28M30ABCDEF' else 6}:12345"
        self.adb.probe.return_value = DeviceProbe(battery_pct=10, charging=False, free_data_bytes=500*1024*1024, device_binding_hash="x")
        with self.assertRaises(PreflightFailed):
            self.coordinator.deploy_active()

    def test_signer_mismatch_results_in_split(self) -> None:
        self._setup_healthy_devices()
        # Only client has wrong signer
        def inspect_fn(endpoint, package_id, inspector):
            if "192.168.1.6" in endpoint:
                return InstalledPackage(package_id="org.danlil.animalheroes", version_code=2, version_name="1.0.0-rc.1", signer_sha256="b"*64)
            return InstalledPackage(package_id="org.danlil.animalheroes", version_code=2, version_name="1.0.0-rc.1", signer_sha256="a"*64)
        self.adb.inspect_installed.side_effect = inspect_fn
        result = self.coordinator.deploy_active()
        self.assertEqual(result.state, DeploymentState.VERSION_SPLIT)

    def test_force_stop_called_before_install(self) -> None:
        self._setup_healthy_devices()
        self.coordinator.deploy_active()
        # force_stop should be called for both devices before any install
        force_stop_calls = self.adb.force_stop.call_args_list
        self.assertEqual(len(force_stop_calls), 2)
