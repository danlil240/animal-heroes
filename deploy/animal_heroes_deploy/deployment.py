"""Two-tablet deployment coordination with preflight, install, and recovery."""

from __future__ import annotations

import time
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Callable

from deploy.animal_heroes_deploy.apk import ApkInspector
from deploy.animal_heroes_deploy.audit import AuditEvent, AuditLog
from deploy.animal_heroes_deploy.catalog import Catalog
from deploy.animal_heroes_deploy.config import DeployConfig
from deploy.animal_heroes_deploy.devices import (
    AdbAdapter,
    DeviceProbe,
    DeviceRejected,
    InstalledPackage,
    TransportError,
)
from deploy.animal_heroes_deploy.domain import DeviceIdentity, DeviceRole, ReleaseRecord


class DeploymentState(str, Enum):
    COMPLETE = "COMPLETE"
    FAILED = "FAILED"
    VERSION_SPLIT = "VERSION_SPLIT"


class DeploymentError(RuntimeError):
    """Raised when a deployment operation fails."""


class PreflightFailed(DeploymentError):
    """Raised when preflight checks fail."""


@dataclass(frozen=True)
class DeploymentResult:
    state: DeploymentState
    host_installed_version: int | None
    client_installed_version: int | None
    host_endpoint: str | None
    client_endpoint: str | None
    error: str | None = None


class DeploymentCoordinator:
    def __init__(
        self,
        *,
        config: DeployConfig,
        catalog: Catalog,
        adb: AdbAdapter,
        apk_inspector: ApkInspector,
        audit_log: AuditLog,
        now_func: Callable[[], str] | None = None,
    ) -> None:
        self._config = config
        self._catalog = catalog
        self._adb = adb
        self._apk_inspector = apk_inspector
        self._audit_log = audit_log
        self._now_func = now_func or (lambda: __import__("datetime").datetime.now(__import__("datetime").timezone.utc).isoformat())
        self._host_identity = next(d for d in config.devices if d.role == DeviceRole.HOST)
        self._client_identity = next(d for d in config.devices if d.role == DeviceRole.CLIENT)

    def deploy_active(self) -> DeploymentResult:
        active = self._catalog.active()
        if active is None:
            raise PreflightFailed("no active release to deploy")
        apk_path = self._catalog.apk_path(active.release_id)
        if apk_path is None or not apk_path.exists():
            raise PreflightFailed("active release artifact not found")
        host_endpoint, host_probe = self._preflight(self._host_identity, active)
        client_endpoint, client_probe = self._preflight(self._client_identity, active)
        if not host_probe.ready_for(active.apk_size):
            raise PreflightFailed("host device not ready (battery/storage)")
        if not client_probe.ready_for(active.apk_size):
            raise PreflightFailed("client device not ready (battery/storage)")
        self._adb.force_stop(host_endpoint, self._config.package_id)
        self._adb.force_stop(client_endpoint, self._config.package_id)
        host_install_ok = self._install_with_retry(host_endpoint, apk_path)
        client_install_ok = self._install_with_retry(client_endpoint, apk_path)
        host_installed = self._verify_installed(host_endpoint, active) if host_install_ok else None
        client_installed = self._verify_installed(client_endpoint, active) if client_install_ok else None
        if host_installed is None and client_installed is None:
            result = DeploymentResult(
                state=DeploymentState.FAILED,
                host_installed_version=None,
                client_installed_version=None,
                host_endpoint=host_endpoint,
                client_endpoint=client_endpoint,
                error="both installations failed",
            )
        elif host_installed is None or client_installed is None:
            result = DeploymentResult(
                state=DeploymentState.VERSION_SPLIT,
                host_installed_version=host_installed.version_code if host_installed else None,
                client_installed_version=client_installed.version_code if client_installed else None,
                host_endpoint=host_endpoint,
                client_endpoint=client_endpoint,
                error="one device installation failed",
            )
        elif host_installed.version_code != active.version_code or client_installed.version_code != active.version_code:
            result = DeploymentResult(
                state=DeploymentState.VERSION_SPLIT,
                host_installed_version=host_installed.version_code,
                client_installed_version=client_installed.version_code,
                host_endpoint=host_endpoint,
                client_endpoint=client_endpoint,
                error="installed version does not match active",
            )
        else:
            result = DeploymentResult(
                state=DeploymentState.COMPLETE,
                host_installed_version=host_installed.version_code,
                client_installed_version=client_installed.version_code,
                host_endpoint=host_endpoint,
                client_endpoint=client_endpoint,
            )
        self._audit_log.append(AuditEvent(
            operation_id=f"deploy-{int(time.time())}",
            timestamp=self._now_func(),
            action="deploy_active",
            initiator="dashboard",
            details={
                "release_id": active.release_id,
                "state": result.state.value,
                "host_endpoint": result.host_endpoint or "",
                "client_endpoint": result.client_endpoint or "",
            },
        ))
        return result

    def retry_failed_device(self, previous: DeploymentResult) -> DeploymentResult:
        if previous.state != DeploymentState.VERSION_SPLIT:
            raise DeploymentError("retry is only valid after a version split")
        active = self._catalog.active()
        if active is None:
            raise PreflightFailed("no active release to deploy")
        apk_path = self._catalog.apk_path(active.release_id)
        if apk_path is None or not apk_path.exists():
            raise PreflightFailed("active release artifact not found")
        if previous.host_installed_version is None:
            identity = self._host_identity
            endpoint = previous.host_endpoint
        elif previous.client_installed_version is None:
            identity = self._client_identity
            endpoint = previous.client_endpoint
        else:
            raise DeploymentError("cannot determine which device to retry")
        if endpoint is None:
            endpoint, _ = self._preflight(identity, active)
        else:
            _, _ = self._preflight(identity, active)
        self._adb.force_stop(endpoint, self._config.package_id)
        install_ok = self._install_with_retry(endpoint, apk_path)
        installed = self._verify_installed(endpoint, active) if install_ok else None
        host_ver = previous.host_installed_version
        client_ver = previous.client_installed_version
        if identity.role == DeviceRole.HOST:
            host_ver = installed.version_code if installed else None
        else:
            client_ver = installed.version_code if installed else None
        if host_ver is None or client_ver is None:
            state = DeploymentState.VERSION_SPLIT
        elif host_ver != active.version_code or client_ver != active.version_code:
            state = DeploymentState.VERSION_SPLIT
        else:
            state = DeploymentState.COMPLETE
        return DeploymentResult(
            state=state,
            host_installed_version=host_ver,
            client_installed_version=client_ver,
            host_endpoint=previous.host_endpoint,
            client_endpoint=previous.client_endpoint,
            error=None if state == DeploymentState.COMPLETE else "retry did not converge",
        )

    def _preflight(self, identity: DeviceIdentity, active: ReleaseRecord) -> tuple[str, DeviceProbe]:
        endpoint = self._adb.resolve(identity.hardware_id)
        if endpoint is None:
            raise PreflightFailed(f"cannot resolve {identity.role.value} device {identity.hardware_id}")
        probe = self._adb.probe(endpoint)
        return endpoint, probe

    def _install_with_retry(self, endpoint: str, apk_path: Path) -> bool:
        try:
            return self._adb.install(endpoint, apk_path)
        except TransportError:
            try:
                return self._adb.install(endpoint, apk_path)
            except TransportError:
                return False

    def _verify_installed(self, endpoint: str, active: ReleaseRecord) -> InstalledPackage | None:
        try:
            installed = self._adb.inspect_installed(endpoint, self._config.package_id, self._apk_inspector)
        except Exception:
            return None
        if installed.version_code != active.version_code:
            return None
        if installed.signer_sha256 != active.signer_sha256:
            return None
        return installed
