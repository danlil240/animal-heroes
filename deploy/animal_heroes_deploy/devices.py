"""Wireless ADB device enrollment, probing, and installation."""

from __future__ import annotations

import hashlib
import re
import shutil
import tempfile
from dataclasses import dataclass
from pathlib import Path

from deploy.animal_heroes_deploy.commands import CommandRunner
from deploy.animal_heroes_deploy.domain import DeviceIdentity, DeviceRole
from deploy.animal_heroes_deploy.toolchain import Tool


EXPECTED_MODEL = "SM-T220"
_MIN_BATTERY_PCT = 25
_MIN_FREE_BYTES = 250 * 1024 * 1024


class DeviceError(RuntimeError):
    """Raised when a device operation fails."""


class DeviceRejected(DeviceError):
    """Raised when a device is not an acceptable SM-T220."""


class PairError(DeviceError):
    """Raised when Wireless ADB pairing fails."""


class TransportError(DeviceError):
    """Raised when a transient ADB transport failure occurs."""


_ENDPOINT_RE = re.compile(r"^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}:\d+$")


@dataclass(frozen=True)
class PairResult:
    success: bool
    message: str

    @classmethod
    def parse(cls, stdout: bytes) -> "PairResult":
        text = stdout.decode("utf-8", errors="replace")
        return cls(success="Successfully" in text or "paired" in text.lower(), message=text.strip())


@dataclass(frozen=True)
class DeviceProbe:
    battery_pct: int
    charging: bool
    free_data_bytes: int
    device_binding_hash: str

    def ready_for(self, apk_size: int) -> bool:
        if self.battery_pct < _MIN_BATTERY_PCT and not self.charging:
            return False
        min_free = max(2 * apk_size, _MIN_FREE_BYTES)
        return self.free_data_bytes >= min_free


@dataclass(frozen=True)
class InstalledPackage:
    package_id: str
    version_code: int
    version_name: str
    signer_sha256: str


def validate_endpoint(address: str) -> str:
    if not _ENDPOINT_RE.fullmatch(address):
        raise DeviceError(f"invalid ADB endpoint: {address}")
    return address


class AdbAdapter:
    def __init__(self, runner: CommandRunner) -> None:
        self._runner = runner

    def pair(self, address: str, code: bytes) -> PairResult:
        validate_endpoint(address)
        code_str = code.decode("ascii").strip()
        result = self._runner.run(
            Tool.ADB,
            ("pair", address),
            stdin=code_str.encode("ascii") + b"\n",
            secret_values=(code_str,),
        )
        return PairResult.parse(result.stdout)

    def connect(self, address: str) -> bool:
        validate_endpoint(address)
        result = self._runner.run(Tool.ADB, ("connect", address))
        text = result.stdout.decode("utf-8", errors="replace")
        return "connected" in text or "already connected" in text

    def shell(self, endpoint: str, args: tuple[str, ...]) -> str:
        validate_endpoint(endpoint)
        result = self._runner.run(Tool.ADB, ("-s", endpoint, "shell", *args))
        if result.returncode != 0:
            raise DeviceError(f"adb shell failed: {args}")
        return result.stdout.decode("utf-8", errors="replace")

    def enroll(self, endpoint: str, role: DeviceRole) -> DeviceIdentity:
        validate_endpoint(endpoint)
        model = self.shell(endpoint, ("getprop", "ro.product.model")).strip()
        hardware_id = (
            self.shell(endpoint, ("getprop", "ro.boot.serialno")).strip()
            or self.shell(endpoint, ("getprop", "ro.serialno")).strip()
        )
        if model != EXPECTED_MODEL or not hardware_id:
            raise DeviceRejected(f"device must be an identifiable {EXPECTED_MODEL}")
        return DeviceIdentity(role=role, hardware_id=hardware_id, last_endpoint=endpoint)

    def resolve(self, hardware_id: str) -> str | None:
        result = self._runner.run(Tool.ADB, ("devices",))
        if result.returncode != 0:
            return None
        text = result.stdout.decode("utf-8", errors="replace")
        for line in text.splitlines():
            parts = line.split()
            if len(parts) >= 2 and parts[1] == "device":
                endpoint = parts[0]
                try:
                    serial = self.shell(endpoint, ("getprop", "ro.boot.serialno")).strip()
                    if not serial:
                        serial = self.shell(endpoint, ("getprop", "ro.serialno")).strip()
                except DeviceError:
                    continue
                if serial == hardware_id:
                    return endpoint
        return None

    def probe(self, endpoint: str) -> DeviceProbe:
        battery_pct = int(self.shell(endpoint, ("dumpsys", "battery", "|", "grep", "level")).split(":")[-1].strip())
        charging_text = self.shell(endpoint, ("dumpsys", "battery", "|", "grep", "status")).strip()
        charging = "charging" in charging_text.lower()
        free_str = self.shell(endpoint, ("df", "/data")).split("\n")[-1].split()[3]
        free_bytes = _parse_size(free_str)
        android_id = self.shell(endpoint, ("settings", "get", "secure", "android_id")).strip()
        binding_hash = hashlib.sha256(android_id.encode("ascii")).hexdigest() if android_id else ""
        return DeviceProbe(
            battery_pct=battery_pct,
            charging=charging,
            free_data_bytes=free_bytes,
            device_binding_hash=binding_hash,
        )

    def inspect_installed(self, endpoint: str, package_id: str, apk_inspector) -> InstalledPackage:
        path_output = self.shell(endpoint, ("pm", "path", package_id)).strip()
        if not path_output.startswith("package:"):
            raise DeviceError(f"package not installed: {package_id}")
        apk_path_on_device = path_output.removeprefix("package:").strip()
        tmp_dir = Path(tempfile.mkdtemp(prefix="adb-pull-"))
        try:
            local_apk = tmp_dir / "base.apk"
            pull_result = self._runner.run(Tool.ADB, ("-s", endpoint, "pull", apk_path_on_device, str(local_apk)))
            if pull_result.returncode != 0:
                raise DeviceError("cannot pull installed APK")
            facts = apk_inspector.inspect(local_apk)
            return InstalledPackage(
                package_id=facts.package_id,
                version_code=facts.version_code,
                version_name=facts.version_name,
                signer_sha256=facts.signer_sha256,
            )
        finally:
            shutil.rmtree(tmp_dir, ignore_errors=True)

    def install(self, endpoint: str, apk_path: Path) -> bool:
        result = self._runner.run(
            Tool.ADB,
            ("-s", endpoint, "install", "-r", str(apk_path)),
            timeout_s=300.0,
        )
        text = result.stdout.decode("utf-8", errors="replace")
        if "Success" in text:
            return True
        if "transport" in text.lower() or "protocol" in text.lower():
            raise TransportError(text.strip())
        return False

    def force_stop(self, endpoint: str, package_id: str) -> None:
        self.shell(endpoint, ("am", "force-stop", package_id))

    def launch(self, endpoint: str, package_id: str) -> None:
        self.shell(endpoint, ("monkey", "-p", package_id, "-c", "android.intent.category.LAUNCHER", "1"))


def _parse_size(text: str) -> int:
    text = text.strip()
    if text.isdigit():
        return int(text)
    match = re.match(r"^(\d+(?:\.\d+)?)([KMGT]?)$", text, re.IGNORECASE)
    if match is None:
        return 0
    value = float(match.group(1))
    suffix = match.group(2).upper()
    multipliers = {"": 1, "K": 1024, "M": 1024**2, "G": 1024**3, "T": 1024**4}
    return int(value * multipliers[suffix])
