"""TLS certificate identity generation and fingerprint management."""

from __future__ import annotations

import hashlib
import re
import subprocess
from dataclasses import dataclass
from pathlib import Path

from deploy.animal_heroes_deploy.commands import CommandRunner
from deploy.animal_heroes_deploy.toolchain import Tool


_CERT_FINGERPRINT_RE = re.compile(r"SHA256 Fingerprint:\s*([0-9A-Fa-f:]+)")


class TlsIdentityError(RuntimeError):
    """Raised when TLS identity generation or inspection fails."""


@dataclass(frozen=True)
class TlsIdentity:
    certificate_path: Path
    key_path: Path
    certificate_sha256: str

    @classmethod
    def ensure(
        cls,
        runner: CommandRunner,
        *,
        certificate_path: Path,
        key_path: Path,
        common_name: str = "animal-heroes-deploy",
    ) -> "TlsIdentity":
        certificate_path.parent.mkdir(parents=True, exist_ok=True)
        key_path.parent.mkdir(parents=True, exist_ok=True)
        if not certificate_path.exists() or not key_path.exists():
            cls._generate(runner, certificate_path, key_path, common_name)
        return cls._load(runner, certificate_path, key_path)

    @staticmethod
    def _generate(
        runner: CommandRunner,
        cert_path: Path,
        key_path: Path,
        common_name: str,
    ) -> None:
        result = runner.run(
            Tool.OPENSSL,
            (
                "req", "-x509", "-newkey", "rsa:2048", "-keyout", str(key_path),
                "-out", str(cert_path), "-days", "3650", "-nodes",
                "-subj", f"/CN={common_name}",
            ),
        )
        if result.returncode != 0:
            raise TlsIdentityError(f"openssl certificate generation failed: {result.redacted_summary}")

    @staticmethod
    def _load(runner: CommandRunner, cert_path: Path, key_path: Path) -> "TlsIdentity":
        result = runner.run(Tool.OPENSSL, ("x509", "-in", str(cert_path), "-noout", "-fingerprint", "-sha256"))
        if result.returncode != 0:
            raise TlsIdentityError("cannot read certificate fingerprint")
        match = _CERT_FINGERPRINT_RE.search(result.stdout.decode("utf-8", errors="replace"))
        if match is None:
            raise TlsIdentityError("certificate fingerprint not found")
        fingerprint = match.group(1).replace(":", "").lower()
        return TlsIdentity(
            certificate_path=cert_path,
            key_path=key_path,
            certificate_sha256=fingerprint,
        )

    @staticmethod
    def certificate_sha256_from_pem(pem: bytes) -> str:
        import tempfile
        with tempfile.NamedTemporaryFile(mode="wb", delete=False, suffix=".pem") as tmp:
            tmp.write(pem)
            tmp_path = Path(tmp.name)
        try:
            result = subprocess.run(
                ("openssl", "x509", "-in", str(tmp_path), "-noout", "-fingerprint", "-sha256"),
                capture_output=True,
                check=False,
            )
            if result.returncode != 0:
                raise TlsIdentityError("cannot read PEM certificate fingerprint")
            match = _CERT_FINGERPRINT_RE.search(result.stdout.decode("utf-8", errors="replace"))
            if match is None:
                raise TlsIdentityError("certificate fingerprint not found")
            return match.group(1).replace(":", "").lower()
        finally:
            tmp_path.unlink(missing_ok=True)
