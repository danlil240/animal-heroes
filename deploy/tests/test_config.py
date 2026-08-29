import json
import tempfile
import unittest
from pathlib import Path

from deploy.animal_heroes_deploy.config import (
    ConfigStore,
    DeployConfig,
    DeployConfigError,
)
from deploy.animal_heroes_deploy.domain import DeviceIdentity, DeviceRole
from deploy.animal_heroes_deploy.paths import StatePaths


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


class DeployConfigTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmpdir = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmpdir.cleanup)
        self.tmp = Path(self._tmpdir.name)

    def test_valid_config_round_trips(self) -> None:
        config = DeployConfig.from_dict(valid_config_dict(self.tmp))
        config.validate()
        self.assertEqual(config.package_id, "org.danlil.animalheroes")
        self.assertEqual(config.devices[0].role, DeviceRole.HOST)
        self.assertEqual(config.devices[1].role, DeviceRole.CLIENT)

    def test_rejects_wrong_package_id(self) -> None:
        data = valid_config_dict(self.tmp)
        data["package_id"] = "com.evil"
        with self.assertRaises(DeployConfigError):
            DeployConfig.from_dict(data)

    def test_rejects_non_private_lan_address(self) -> None:
        data = valid_config_dict(self.tmp)
        data["lan_address"] = "8.8.8.8"
        with self.assertRaises(DeployConfigError):
            DeployConfig.from_dict(data)

    def test_rejects_keystore_inside_state_root(self) -> None:
        data = valid_config_dict(self.tmp)
        state_root = self.tmp / "state"
        state_root.mkdir()
        keystore = state_root / "release.keystore"
        keystore.write_bytes(b"dummy")
        data["keystore_path"] = str(keystore)
        data["state_root"] = str(state_root)
        with self.assertRaises(DeployConfigError):
            DeployConfig.from_dict(data)

    def test_rejects_duplicate_hardware_ids(self) -> None:
        data = valid_config_dict(self.tmp)
        data["devices"] = [
            {"role": "host", "hardware_id": "SAME123"},
            {"role": "client", "hardware_id": "SAME123"},
        ]
        with self.assertRaises(DeployConfigError):
            DeployConfig.from_dict(data)

    def test_rejects_missing_device_role(self) -> None:
        data = valid_config_dict(self.tmp)
        data["devices"] = [
            {"role": "host", "hardware_id": "R28M30ABCDEF"},
            {"role": "host", "hardware_id": "R28M30GHIJKL"},
        ]
        with self.assertRaises(DeployConfigError):
            DeployConfig.from_dict(data)

    def test_rejects_unknown_keys(self) -> None:
        data = valid_config_dict(self.tmp)
        data["unexpected"] = True
        with self.assertRaises(DeployConfigError):
            DeployConfig.from_dict(data)

    def test_rejects_secret_fields(self) -> None:
        data = valid_config_dict(self.tmp)
        data["keystore_password"] = "secret"
        with self.assertRaises(DeployConfigError):
            DeployConfig.from_dict(data)


class ConfigStoreTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmpdir = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmpdir.cleanup)
        self.paths = StatePaths.for_test(Path(self._tmpdir.name))

    def test_save_and_load_round_trip(self) -> None:
        store = ConfigStore(self.paths)
        config = DeployConfig.from_dict(valid_config_dict(Path(self._tmpdir.name)))
        store.save_atomic(config)
        loaded = store.load()
        self.assertEqual(loaded, config)

    def test_load_returns_none_when_absent(self) -> None:
        store = ConfigStore(self.paths)
        self.assertIsNone(store.load())
