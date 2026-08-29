"""APK inspection and verification using aapt and apksigner."""

from __future__ import annotations

import hashlib
import re
from dataclasses import dataclass, field
from pathlib import Path

from deploy.animal_heroes_deploy.commands import CommandRunner
from deploy.animal_heroes_deploy.config import PACKAGE_ID, REQUIRED_PERMISSIONS
from deploy.animal_heroes_deploy.toolchain import Tool


class ApkInspectionError(ValueError):
    """Raised when APK inspection fails or produces invalid results."""


class ApkVerificationError(ValueError):
    """Raised when APK verification fails."""


@dataclass(frozen=True)
class ApkFacts:
    package_id: str
    version_name: str
    version_code: int
    permissions: frozenset[str]
    signer_sha256: str
    apk_sha256: str
    apk_size: int


class ApkInspector:
    def __init__(self, runner: CommandRunner) -> None:
        self._runner = runner

    def inspect(self, apk_path: Path) -> ApkFacts:
        package_id, version_name, version_code = self._dump_badging(apk_path)
        permissions = self._dump_permissions(apk_path)
        signer_sha256 = self._verify_signature(apk_path)
        apk_sha256 = _compute_sha256(apk_path)
        apk_size = apk_path.stat().st_size
        return ApkFacts(
            package_id=package_id,
            version_name=version_name,
            version_code=version_code,
            permissions=permissions,
            signer_sha256=signer_sha256,
            apk_sha256=apk_sha256,
            apk_size=apk_size,
        )

    def verify(
        self,
        apk_path: Path,
        *,
        expected_package_id: str = PACKAGE_ID,
        expected_version_name: str,
        expected_version_code: int,
        expected_signer_sha256: str,
        expected_apk_sha256: str,
    ) -> ApkFacts:
        facts = self.inspect(apk_path)
        if facts.package_id != expected_package_id:
            raise ApkVerificationError(f"package ID mismatch: {facts.package_id}")
        if facts.version_name != expected_version_name:
            raise ApkVerificationError(f"version name mismatch: {facts.version_name}")
        if facts.version_code != expected_version_code:
            raise ApkVerificationError(f"version code mismatch: {facts.version_code}")
        if facts.permissions != REQUIRED_PERMISSIONS:
            raise ApkVerificationError(f"permission set mismatch: {sorted(facts.permissions)}")
        if facts.signer_sha256 != expected_signer_sha256:
            raise ApkVerificationError("signer fingerprint mismatch")
        if facts.apk_sha256 != expected_apk_sha256:
            raise ApkVerificationError("APK checksum mismatch")
        return facts

    def _dump_badging(self, apk_path: Path) -> tuple[str, str, int]:
        result = self._runner.run(Tool.AAPT, ("dump", "badging", str(apk_path)))
        if result.returncode != 0:
            raise ApkInspectionError("aapt dump badging failed")
        output = result.stdout.decode("utf-8", errors="replace")
        pkg_match = re.search(r"^package: name='([^']+)' versionName='([^']+)' versionCode='(\d+)'", output, re.MULTILINE)
        if pkg_match is None:
            raise ApkInspectionError("cannot parse package metadata")
        return pkg_match.group(1), pkg_match.group(2), int(pkg_match.group(3))

    def _dump_permissions(self, apk_path: Path) -> frozenset[str]:
        result = self._runner.run(Tool.AAPT, ("dump", "permissions", str(apk_path)))
        if result.returncode != 0:
            raise ApkInspectionError("aapt dump permissions failed")
        output = result.stdout.decode("utf-8", errors="replace")
        permissions: set[str] = set()
        for line in output.splitlines():
            match = re.match(r"^uses-permission(?:-sdk-23)?:\s+name='([^']+)'", line)
            if match:
                permissions.add(match.group(1))
        return frozenset(permissions)

    def _verify_signature(self, apk_path: Path) -> str:
        result = self._runner.run(
            Tool.APKSIGNER,
            ("verify", "--verbose", "--print-certs", str(apk_path)),
        )
        if result.returncode != 0:
            raise ApkInspectionError("apksigner verify failed")
        output = result.stdout.decode("utf-8", errors="replace")
        cert_match = re.search(r"SHA-256(?:\s+digest)?:\s*([0-9a-fA-F:]+)", output)
        if cert_match is None:
            raise ApkInspectionError("cannot parse signer certificate")
        return cert_match.group(1).replace(":", "").lower()


def _compute_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        while True:
            chunk = f.read(65536)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()
