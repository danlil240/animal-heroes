"""Non-secret deployment configuration with strict validation."""

from __future__ import annotations

import ipaddress
import json
import os
import re
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Mapping

from deploy.animal_heroes_deploy.domain import DeviceIdentity, DeviceRole
from deploy.animal_heroes_deploy.paths import StatePaths


PACKAGE_ID = "org.danlil.animalheroes"
REQUIRED_PERMISSIONS = frozenset(
    {"INTERNET", "ACCESS_NETWORK_STATE", "ACCESS_WIFI_STATE", "CHANGE_WIFI_MULTICAST_STATE"}
)
_HEX64 = re.compile(r"^[0-9a-f]{64}$")
_HARDWARE_ID = re.compile(r"^[A-Za-z0-9]{6,32}$")

_CONFIG_KEYS = frozenset(
    {
        "package_id",
        "lan_address",
        "lan_port",
        "dashboard_port",
        "discovery_port",
        "keystore_path",
        "keystore_alias",
        "pinned_signer_sha256",
        "devices",
        "retention",
        "state_root",
    }
)
_REQUIRED_CONFIG_KEYS = frozenset(
    {
        "package_id",
        "lan_address",
        "lan_port",
        "dashboard_port",
        "discovery_port",
        "keystore_path",
        "keystore_alias",
        "pinned_signer_sha256",
        "devices",
        "retention",
    }
)
_SECRET_FIELD_NAMES = frozenset(
    {"password", "token", "secret", "key", "passphrase", "keystore_password", "api_key"}
)


class DeployConfigError(ValueError):
    """Raised when deployment configuration is invalid."""


def _is_private_ipv4(address: str) -> bool:
    try:
        addr = ipaddress.IPv4Address(address)
    except ipaddress.AddressValueError:
        return False
    return addr.is_private and not addr.is_loopback and not addr.is_link_local


def _is_relative_to(path: Path, base: Path) -> bool:
    try:
        path.relative_to(base)
        return True
    except ValueError:
        return False


@dataclass(frozen=True)
class DeployConfig:
    package_id: str
    lan_address: str
    lan_port: int
    dashboard_port: int
    discovery_port: int
    keystore_path: Path
    keystore_alias: str
    pinned_signer_sha256: str
    devices: tuple[DeviceIdentity, ...]
    retention: str
    state_root: Path | None = None

    @classmethod
    def from_dict(cls, value: Mapping[str, object]) -> "DeployConfig":
        keys = set(value)
        unknown = keys - _CONFIG_KEYS
        if unknown:
            raise DeployConfigError(f"unknown configuration keys: {sorted(unknown)}")
        missing = _REQUIRED_CONFIG_KEYS - keys
        if missing:
            raise DeployConfigError(f"missing configuration keys: {sorted(missing)}")
        for secret_name in _SECRET_FIELD_NAMES:
            if secret_name in keys:
                raise DeployConfigError(f"secret field '{secret_name}' must not appear in configuration")
        package_id = str(value["package_id"])
        if package_id != PACKAGE_ID:
            raise DeployConfigError("package_id must be org.danlil.animalheroes")
        lan_address = str(value["lan_address"])
        if not _is_private_ipv4(lan_address):
            raise DeployConfigError("lan_address must be a private IPv4 address")
        lan_port = int(value["lan_port"])
        dashboard_port = int(value["dashboard_port"])
        discovery_port = int(value["discovery_port"])
        for port in (lan_port, dashboard_port, discovery_port):
            if not (1 <= port <= 65535):
                raise DeployConfigError("ports must be between 1 and 65535")
        keystore_path = Path(str(value["keystore_path"])).resolve(strict=False)
        keystore_alias = str(value["keystore_alias"])
        if not keystore_alias:
            raise DeployConfigError("keystore_alias must not be empty")
        pinned_signer = str(value["pinned_signer_sha256"])
        if not _HEX64.fullmatch(pinned_signer):
            raise DeployConfigError("pinned_signer_sha256 must be 64 lowercase hex characters")
        state_root_raw = value.get("state_root")
        state_root = Path(str(state_root_raw)).resolve(strict=False) if state_root_raw else None
        if state_root is not None:
            keystore_resolved = keystore_path.resolve(strict=False)
            if keystore_resolved == state_root or _is_relative_to(keystore_resolved, state_root):
                raise DeployConfigError("keystore_path must be outside the state root")
        devices = _parse_devices(value["devices"])
        retention = str(value["retention"])
        if retention != "retain_all":
            raise DeployConfigError("retention must be 'retain_all' in version one")
        return cls(
            package_id=package_id,
            lan_address=lan_address,
            lan_port=lan_port,
            dashboard_port=dashboard_port,
            discovery_port=discovery_port,
            keystore_path=keystore_path,
            keystore_alias=keystore_alias,
            pinned_signer_sha256=pinned_signer,
            devices=devices,
            retention=retention,
            state_root=state_root,
        )

    def validate(self) -> None:
        self.from_dict(self.to_dict())

    def to_dict(self) -> dict[str, object]:
        result: dict[str, object] = {
            "package_id": self.package_id,
            "lan_address": self.lan_address,
            "lan_port": self.lan_port,
            "dashboard_port": self.dashboard_port,
            "discovery_port": self.discovery_port,
            "keystore_path": str(self.keystore_path),
            "keystore_alias": self.keystore_alias,
            "pinned_signer_sha256": self.pinned_signer_sha256,
            "devices": [
                {"role": d.role.value, "hardware_id": d.hardware_id, "last_endpoint": d.last_endpoint}
                for d in self.devices
            ],
            "retention": self.retention,
        }
        if self.state_root is not None:
            result["state_root"] = str(self.state_root)
        return result


def _parse_devices(value: object) -> tuple[DeviceIdentity, ...]:
    if not isinstance(value, (list, tuple)) or len(value) != 2:
        raise DeployConfigError("exactly two devices are required")
    devices: list[DeviceIdentity] = []
    for entry in value:
        if not isinstance(entry, dict):
            raise DeployConfigError("each device must be an object")
        if set(entry) - {"role", "hardware_id", "last_endpoint"}:
            raise DeployConfigError("unknown device field")
        if "role" not in entry or "hardware_id" not in entry:
            raise DeployConfigError("device must have role and hardware_id")
        role_str = str(entry["role"])
        try:
            role = DeviceRole(role_str)
        except ValueError:
            raise DeployConfigError(f"device role must be host or client, got '{role_str}'")
        hardware_id = str(entry["hardware_id"])
        if not _HARDWARE_ID.fullmatch(hardware_id):
            raise DeployConfigError("hardware_id must be 6-32 alphanumeric characters")
        endpoint = str(entry.get("last_endpoint", ""))
        devices.append(DeviceIdentity(role=role, hardware_id=hardware_id, last_endpoint=endpoint))
    roles = {d.role for d in devices}
    if roles != {DeviceRole.HOST, DeviceRole.CLIENT}:
        raise DeployConfigError("devices must have one host and one client role")
    ids = [d.hardware_id for d in devices]
    if len(set(ids)) != 2:
        raise DeployConfigError("devices must have distinct hardware identities")
    return tuple(devices)


class ConfigStore:
    def __init__(self, paths: StatePaths) -> None:
        self._paths = paths

    def load(self) -> DeployConfig | None:
        path = self._paths.config_file_path
        if not path.exists():
            return None
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            raise DeployConfigError("configuration cannot be loaded") from error
        if not isinstance(data, dict):
            raise DeployConfigError("configuration must be an object")
        return DeployConfig.from_dict(data)

    def save_atomic(self, config: DeployConfig) -> None:
        config.validate()
        path = self._paths.config_file_path
        path.parent.mkdir(parents=True, exist_ok=True)
        os.chmod(path.parent, 0o700)
        content = json.dumps(config.to_dict(), indent=2, sort_keys=True)
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", dir=path.parent, prefix=".config.", delete=False
        ) as tmp:
            tmp.write(content)
            tmp.flush()
            os.fsync(tmp.fileno())
            tmp_path = Path(tmp.name)
        os.chmod(tmp_path, 0o600)
        os.replace(tmp_path, path)
