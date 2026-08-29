import unittest
from datetime import datetime, timedelta, timezone

from deploy.animal_heroes_deploy.domain import DeviceRole
from deploy.animal_heroes_deploy.pairing import (
    PairingAlreadyUsed,
    PairingError,
    PairingManager,
    PairingSessionExpired,
    PairingSessionNotOpen,
)


NOW = datetime(2026, 8, 29, 10, 0, 0, tzinfo=timezone.utc)
CERT_SHA = "a" * 64


class PairingManagerTests(unittest.TestCase):
    def test_open_and_accept_round_trip(self) -> None:
        manager = PairingManager(random_bytes=lambda n: b"x" * n)
        session = manager.open(
            certificate_sha256=CERT_SHA,
            intended_role=DeviceRole.HOST,
            intended_hardware_id="R28M30ABCDEF",
            now=NOW,
        )
        self.assertTrue(manager.is_open(NOW))
        code = manager.code()
        result = manager.accept(
            entered_code=code,
            client_id="client_1",
            observed_certificate_sha256=CERT_SHA,
            hardware_id="R28M30ABCDEF",
            now=NOW,
        )
        self.assertEqual(result.role, DeviceRole.HOST)
        self.assertEqual(result.client_id, "client_1")
        self.assertEqual(len(result.token), 32)

    def test_accept_rejects_wrong_code(self) -> None:
        manager = PairingManager(random_bytes=lambda n: b"y" * n)
        manager.open(
            certificate_sha256=CERT_SHA,
            intended_role=DeviceRole.CLIENT,
            intended_hardware_id="R28M30GHIJKL",
            now=NOW,
        )
        with self.assertRaises(PairingError):
            manager.accept(
                entered_code="000000",
                client_id="client_1",
                observed_certificate_sha256=CERT_SHA,
                hardware_id="R28M30GHIJKL",
                now=NOW,
            )

    def test_accept_rejects_certificate_mismatch(self) -> None:
        manager = PairingManager(random_bytes=lambda n: b"z" * n)
        manager.open(
            certificate_sha256=CERT_SHA,
            intended_role=DeviceRole.HOST,
            intended_hardware_id="R28M30ABCDEF",
            now=NOW,
        )
        code = manager.code()
        with self.assertRaises(PairingError):
            manager.accept(
                entered_code=code,
                client_id="client_1",
                observed_certificate_sha256="b" * 64,
                hardware_id="R28M30ABCDEF",
                now=NOW,
            )

    def test_accept_rejects_hardware_mismatch(self) -> None:
        manager = PairingManager(random_bytes=lambda n: b"w" * n)
        manager.open(
            certificate_sha256=CERT_SHA,
            intended_role=DeviceRole.HOST,
            intended_hardware_id="R28M30ABCDEF",
            now=NOW,
        )
        code = manager.code()
        with self.assertRaises(PairingError):
            manager.accept(
                entered_code=code,
                client_id="client_1",
                observed_certificate_sha256=CERT_SHA,
                hardware_id="WRONG123",
                now=NOW,
            )

    def test_expired_session_rejected(self) -> None:
        manager = PairingManager(ttl=timedelta(minutes=5), random_bytes=lambda n: b"v" * n)
        manager.open(
            certificate_sha256=CERT_SHA,
            intended_role=DeviceRole.HOST,
            intended_hardware_id="R28M30ABCDEF",
            now=NOW,
        )
        code = manager.code()
        with self.assertRaises(PairingSessionExpired):
            manager.accept(
                entered_code=code,
                client_id="client_1",
                observed_certificate_sha256=CERT_SHA,
                hardware_id="R28M30ABCDEF",
                now=NOW + timedelta(minutes=6),
            )

    def test_already_used_rejected(self) -> None:
        manager = PairingManager(random_bytes=lambda n: b"u" * n)
        manager.open(
            certificate_sha256=CERT_SHA,
            intended_role=DeviceRole.HOST,
            intended_hardware_id="R28M30ABCDEF",
            now=NOW,
        )
        code = manager.code()
        manager.accept(
            entered_code=code,
            client_id="client_1",
            observed_certificate_sha256=CERT_SHA,
            hardware_id="R28M30ABCDEF",
            now=NOW,
        )
        with self.assertRaises(PairingAlreadyUsed):
            manager.accept(
                entered_code=code,
                client_id="client_2",
                observed_certificate_sha256=CERT_SHA,
                hardware_id="R28M30ABCDEF",
                now=NOW,
            )

    def test_accept_without_open_raises(self) -> None:
        manager = PairingManager()
        with self.assertRaises(PairingSessionNotOpen):
            manager.accept(
                entered_code="123456",
                client_id="client_1",
                observed_certificate_sha256=CERT_SHA,
                hardware_id="R28M30ABCDEF",
                now=NOW,
            )

    def test_revoke_closes_session(self) -> None:
        manager = PairingManager(random_bytes=lambda n: b"t" * n)
        manager.open(
            certificate_sha256=CERT_SHA,
            intended_role=DeviceRole.HOST,
            intended_hardware_id="R28M30ABCDEF",
            now=NOW,
        )
        manager.revoke()
        self.assertFalse(manager.is_open(NOW))
