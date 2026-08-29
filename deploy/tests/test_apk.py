import hashlib
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

from deploy.animal_heroes_deploy.apk import (
    ApkFacts,
    ApkInspectionError,
    ApkInspector,
    ApkVerificationError,
)
from deploy.animal_heroes_deploy.config import PACKAGE_ID, REQUIRED_PERMISSIONS
from deploy.animal_heroes_deploy.toolchain import Tool


def make_apk(path: Path, content: bytes = b"fake-apk-content") -> Path:
    path.write_bytes(content)
    return path


BADGING_OUTPUT = (
    "package: name='org.danlil.animalheroes' versionName='1.0.0-rc.1' versionCode='2'\n"
    "launchable-activity: name='org.danlil.animalheroes.MainActivity'\n"
)
PERMISSIONS_OUTPUT = (
    "package: org.danlil.animalheroes\n"
    "uses-permission: name='INTERNET'\n"
    "uses-permission: name='ACCESS_NETWORK_STATE'\n"
    "uses-permission: name='ACCESS_WIFI_STATE'\n"
    "uses-permission: name='CHANGE_WIFI_MULTICAST_STATE'\n"
)
APKSIGNER_OUTPUT = (
    "Verifies\n"
    "Verified using v1 scheme (JAR signing): false\n"
    "Verified using v2 scheme (APK Signature Scheme v2): true\n"
    "Number of signers: 1\n"
    "Signer #1 certificate SHA-256 digest: ab:cd:ef:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00\n"
)


class ApkInspectorTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmpdir = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmpdir.cleanup)
        self.apk = make_apk(Path(self._tmpdir.name) / "test.apk")

    def _make_inspector(self, badging=BADGING_OUTPUT, permissions=PERMISSIONS_OUTPUT, apksigner=APKSIGNER_OUTPUT, apksigner_rc=0) -> ApkInspector:
        runner = MagicMock()
        def run_fn(tool, args, **kwargs):
            if tool == Tool.AAPT and "badging" in args:
                return MagicMock(returncode=0, stdout=badging.encode(), stderr=b"")
            if tool == Tool.AAPT and "permissions" in args:
                return MagicMock(returncode=0, stdout=permissions.encode(), stderr=b"")
            if tool == Tool.APKSIGNER:
                return MagicMock(returncode=apksigner_rc, stdout=apksigner.encode(), stderr=b"")
            return MagicMock(returncode=1, stdout=b"", stderr=b"error")
        runner.run.side_effect = run_fn
        return ApkInspector(runner)

    def test_inspect_parses_facts(self) -> None:
        inspector = self._make_inspector()
        facts = inspector.inspect(self.apk)
        self.assertEqual(facts.package_id, "org.danlil.animalheroes")
        self.assertEqual(facts.version_name, "1.0.0-rc.1")
        self.assertEqual(facts.version_code, 2)
        self.assertEqual(facts.permissions, REQUIRED_PERMISSIONS)
        self.assertEqual(facts.signer_sha256, "abcdef" + "0" * 58)
        self.assertEqual(facts.apk_sha256, hashlib.sha256(b"fake-apk-content").hexdigest())

    def test_verify_accepts_matching_apk(self) -> None:
        inspector = self._make_inspector()
        facts = inspector.verify(
            self.apk,
            expected_version_name="1.0.0-rc.1",
            expected_version_code=2,
            expected_signer_sha256="abcdef" + "0" * 58,
            expected_apk_sha256=hashlib.sha256(b"fake-apk-content").hexdigest(),
        )
        self.assertEqual(facts.version_code, 2)

    def test_verify_rejects_wrong_package(self) -> None:
        inspector = self._make_inspector()
        with self.assertRaises(ApkVerificationError):
            inspector.verify(
                self.apk,
                expected_package_id="com.evil",
                expected_version_name="1.0.0-rc.1",
                expected_version_code=2,
                expected_signer_sha256="abcdef" + "0" * 58,
                expected_apk_sha256=hashlib.sha256(b"fake-apk-content").hexdigest(),
            )

    def test_verify_rejects_wrong_signer(self) -> None:
        inspector = self._make_inspector()
        with self.assertRaises(ApkVerificationError):
            inspector.verify(
                self.apk,
                expected_version_name="1.0.0-rc.1",
                expected_version_code=2,
                expected_signer_sha256="b" * 64,
                expected_apk_sha256=hashlib.sha256(b"fake-apk-content").hexdigest(),
            )

    def test_verify_rejects_wrong_checksum(self) -> None:
        inspector = self._make_inspector()
        with self.assertRaises(ApkVerificationError):
            inspector.verify(
                self.apk,
                expected_version_name="1.0.0-rc.1",
                expected_version_code=2,
                expected_signer_sha256="abcdef" + "0" * 58,
                expected_apk_sha256="0" * 64,
            )

    def test_verify_rejects_extra_permission(self) -> None:
        extra = PERMISSIONS_OUTPUT + "uses-permission: name='android.permission.CAMERA'\n"
        inspector = self._make_inspector(permissions=extra)
        with self.assertRaises(ApkVerificationError):
            inspector.verify(
                self.apk,
                expected_version_name="1.0.0-rc.1",
                expected_version_code=2,
                expected_signer_sha256="abcdef" + "0" * 58,
                expected_apk_sha256=hashlib.sha256(b"fake-apk-content").hexdigest(),
            )

    def test_inspect_rejects_aapt_failure(self) -> None:
        inspector = self._make_inspector(badging="")
        with self.assertRaises(ApkInspectionError):
            inspector.inspect(self.apk)

    def test_inspect_rejects_apksigner_failure(self) -> None:
        inspector = self._make_inspector(apksigner_rc=1, apksigner="")
        with self.assertRaises(ApkInspectionError):
            inspector.inspect(self.apk)
