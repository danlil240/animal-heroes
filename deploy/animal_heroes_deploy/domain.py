"""Immutable domain models for releases, devices, and deployments."""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Mapping

from deploy.animal_heroes_deploy.release_metadata import ReleaseMetadata


class ReleaseChannel(str, Enum):
    CANDIDATE = "candidate"
    STABLE = "stable"


class DeviceRole(str, Enum):
    HOST = "host"
    CLIENT = "client"


class DeploymentState(str, Enum):
    PENDING = "pending"
    COMPLETE = "complete"
    FAILED = "failed"
    VERSION_SPLIT = "version_split"


@dataclass(frozen=True)
class DeviceIdentity:
    role: DeviceRole
    hardware_id: str
    last_endpoint: str = ""

    def with_endpoint(self, endpoint: str) -> "DeviceIdentity":
        return DeviceIdentity(role=self.role, hardware_id=self.hardware_id, last_endpoint=endpoint)


@dataclass(frozen=True)
class DeploymentRecord:
    device_role: DeviceRole
    hardware_id: str
    state: DeploymentState
    version_code: int
    started_at: str
    completed_at: str
    error: str | None = None


@dataclass(frozen=True)
class ReleaseRecord:
    release_id: str
    version_name: str
    version_code: int
    channel: ReleaseChannel
    source_commit: str
    release_commit: str
    tag: str
    built_at: str
    package_id: str
    apk_size: int
    apk_sha256: str
    signer_sha256: str
    permissions: frozenset[str]
    managed_metadata: ReleaseMetadata
    rollback_of: str | None
    deployments: tuple[DeploymentRecord, ...] = ()

    @classmethod
    def from_dict(cls, value: Mapping[str, object]) -> "ReleaseRecord":
        return cls(
            release_id=str(value["release_id"]),
            version_name=str(value["version_name"]),
            version_code=int(value["version_code"]),
            channel=ReleaseChannel(str(value["channel"])),
            source_commit=str(value["source_commit"]),
            release_commit=str(value["release_commit"]),
            tag=str(value["tag"]),
            built_at=str(value["built_at"]),
            package_id=str(value["package_id"]),
            apk_size=int(value["apk_size"]),
            apk_sha256=str(value["apk_sha256"]),
            signer_sha256=str(value["signer_sha256"]),
            permissions=frozenset(str(p) for p in value["permissions"]),
            managed_metadata=ReleaseMetadata.from_dict(value["managed_metadata"]),  # type: ignore[arg-type]
            rollback_of=value.get("rollback_of") if value.get("rollback_of") is not None else None,
            deployments=tuple(
                DeploymentRecord(
                    device_role=DeviceRole(str(d["device_role"])),
                    hardware_id=str(d["hardware_id"]),
                    state=DeploymentState(str(d["state"])),
                    version_code=int(d["version_code"]),
                    started_at=str(d["started_at"]),
                    completed_at=str(d["completed_at"]),
                    error=d.get("error") if d.get("error") is not None else None,
                )
                for d in value.get("deployments", ())
            ),
        )

    def to_dict(self) -> dict[str, object]:
        return {
            "release_id": self.release_id,
            "version_name": self.version_name,
            "version_code": self.version_code,
            "channel": self.channel.value,
            "source_commit": self.source_commit,
            "release_commit": self.release_commit,
            "tag": self.tag,
            "built_at": self.built_at,
            "package_id": self.package_id,
            "apk_size": self.apk_size,
            "apk_sha256": self.apk_sha256,
            "signer_sha256": self.signer_sha256,
            "permissions": sorted(self.permissions),
            "managed_metadata": {
                "version_name": self.managed_metadata.version_name,
                "version_code": self.managed_metadata.version_code,
                "application_protocol_version": self.managed_metadata.application_protocol_version,
                "save_schema_version": self.managed_metadata.save_schema_version,
                "save_schema_compatible_min": self.managed_metadata.save_schema_compatible_min,
                "save_schema_compatible_max": self.managed_metadata.save_schema_compatible_max,
            },
            "rollback_of": self.rollback_of,
            "deployments": [
                {
                    "device_role": d.device_role.value,
                    "hardware_id": d.hardware_id,
                    "state": d.state.value,
                    "version_code": d.version_code,
                    "started_at": d.started_at,
                    "completed_at": d.completed_at,
                    "error": d.error,
                }
                for d in self.deployments
            ],
        }

    def with_deployment(self, record: DeploymentRecord) -> "ReleaseRecord":
        return ReleaseRecord(
            **{**self.__dict__, "deployments": (*self.deployments, record)}
        )
