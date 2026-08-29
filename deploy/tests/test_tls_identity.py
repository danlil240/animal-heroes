import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

from deploy.animal_heroes_deploy.commands import CommandResult
from deploy.animal_heroes_deploy.tls_identity import TlsIdentity, TlsIdentityError
from deploy.animal_heroes_deploy.toolchain import Tool


class TlsIdentityTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmpdir = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmpdir.cleanup)
        self.cert_path = Path(self._tmpdir.name) / "cert.pem"
        self.key_path = Path(self._tmpdir.name) / "key.pem"

    def test_ensure_generates_and_loads_fingerprint(self) -> None:
        runner = MagicMock()
        gen_result = MagicMock(returncode=0, stdout=b"", stderr=b"")
        fp_result = MagicMock(returncode=0, stdout=b"SHA256 Fingerprint: AB:CD:EF:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00\n", stderr=b"")
        runner.run.side_effect = [gen_result, fp_result]
        identity = TlsIdentity.ensure(runner, certificate_path=self.cert_path, key_path=self.key_path)
        self.assertEqual(identity.certificate_sha256, "abcdef" + "0" * 58)
        self.assertEqual(identity.certificate_path, self.cert_path)
        self.assertEqual(identity.key_path, self.key_path)

    def test_ensure_reuses_existing_certificate(self) -> None:
        self.cert_path.write_text("existing cert", encoding="utf-8")
        self.key_path.write_text("existing key", encoding="utf-8")
        runner = MagicMock()
        fp_result = MagicMock(returncode=0, stdout=b"SHA256 Fingerprint: 11:22:33:44:55:66:77:88:99:00:11:22:33:44:55:66:77:88:99:00:11:22:33:44:55:66:77:88:99:00:11:22\n", stderr=b"")
        runner.run.return_value = fp_result
        identity = TlsIdentity.ensure(runner, certificate_path=self.cert_path, key_path=self.key_path)
        self.assertEqual(len(identity.certificate_sha256), 64)
        # Should not call generate (only fingerprint read)
        self.assertEqual(runner.run.call_count, 1)

    def test_generation_failure_raises(self) -> None:
        runner = MagicMock()
        runner.run.return_value = MagicMock(returncode=1, stdout=b"", stderr=b"error")
        with self.assertRaises(TlsIdentityError):
            TlsIdentity.ensure(runner, certificate_path=self.cert_path, key_path=self.key_path)
