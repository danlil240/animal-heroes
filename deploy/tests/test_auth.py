import base64
import hashlib
import hmac
import unittest
from datetime import datetime, timedelta, timezone

from deploy.animal_heroes_deploy.auth import (
    AuthenticationError,
    ChallengeRejected,
    ChallengeStore,
    canonical_auth_message,
    pairing_code,
    sign_message,
)


NOW = datetime(2026, 8, 29, 10, 0, 0, tzinfo=timezone.utc)


class CanonicalAuthMessageTests(unittest.TestCase):
    def test_fixed_vector(self) -> None:
        message = canonical_auth_message("client_1", "update_both", "challenge_1")
        expected = b"animal-heroes-update-v1\nclient_1\nupdate_both\nchallenge_1\n"
        self.assertEqual(message, expected)

    def test_rejects_invalid_fields(self) -> None:
        for client_id, action, challenge in [
            ("client 1", "update_both", "challenge_1"),
            ("client_1", "update both", "challenge_1"),
            ("client_1", "update_both", "challenge 1"),
            ("", "update_both", "challenge_1"),
        ]:
            with self.subTest(client_id=client_id, action=action, challenge=challenge), self.assertRaises(AuthenticationError):
                canonical_auth_message(client_id, action, challenge)


class SignMessageTests(unittest.TestCase):
    def test_fixed_vector(self) -> None:
        token = bytes.fromhex("00" * 32)
        message = canonical_auth_message("client_1", "update_both", "challenge_1")
        expected = base64.b64encode(hmac.digest(token, message, "sha256")).decode()
        self.assertEqual(sign_message(token, message), expected)

    def test_rejects_wrong_token_length(self) -> None:
        with self.assertRaises(AuthenticationError):
            sign_message(b"short", b"message")


class PairingCodeTests(unittest.TestCase):
    def test_six_digit_code(self) -> None:
        cert_sha = "a" * 64
        nonce = "nonce123"
        code = pairing_code(cert_sha, nonce)
        self.assertEqual(len(code), 6)
        self.assertTrue(code.isdigit())

    def test_deterministic(self) -> None:
        cert_sha = "b" * 64
        nonce = "nonce456"
        self.assertEqual(pairing_code(cert_sha, nonce), pairing_code(cert_sha, nonce))

    def test_different_inputs_different_codes(self) -> None:
        cert_sha = "a" * 64
        self.assertNotEqual(pairing_code(cert_sha, "nonce1"), pairing_code(cert_sha, "nonce2"))

    def test_rejects_invalid_cert_sha(self) -> None:
        with self.assertRaises(AuthenticationError):
            pairing_code("short", "nonce")


class ChallengeStoreTests(unittest.TestCase):
    def test_fixed_vector_and_single_use(self) -> None:
        token = bytes.fromhex("00" * 32)
        store = ChallengeStore(ttl=timedelta(seconds=30), random_bytes=lambda n: b"a" * n)
        challenge = store.issue("client_1", "update_both", NOW)
        signature = sign_message(token, canonical_auth_message("client_1", "update_both", challenge.challenge_id))
        store.verify_and_consume("client_1", "update_both", challenge.challenge_id, signature, token, NOW)
        with self.assertRaises(ChallengeRejected):
            store.verify_and_consume("client_1", "update_both", challenge.challenge_id, signature, token, NOW)

    def test_expired_challenge_rejected(self) -> None:
        token = bytes.fromhex("00" * 32)
        store = ChallengeStore(ttl=timedelta(seconds=30), random_bytes=lambda n: b"b" * n)
        challenge = store.issue("client_1", "update_both", NOW)
        signature = sign_message(token, canonical_auth_message("client_1", "update_both", challenge.challenge_id))
        with self.assertRaises(ChallengeRejected):
            store.verify_and_consume("client_1", "update_both", challenge.challenge_id, signature, token, NOW + timedelta(seconds=31))

    def test_wrong_hmac_rejected(self) -> None:
        token = bytes.fromhex("00" * 32)
        store = ChallengeStore(random_bytes=lambda n: b"c" * n)
        challenge = store.issue("client_1", "update_both", NOW)
        with self.assertRaises(ChallengeRejected):
            store.verify_and_consume("client_1", "update_both", challenge.challenge_id, "wrong-signature", token, NOW)

    def test_wrong_action_rejected(self) -> None:
        token = bytes.fromhex("00" * 32)
        store = ChallengeStore(random_bytes=lambda n: b"d" * n)
        challenge = store.issue("client_1", "update_both", NOW)
        signature = sign_message(token, canonical_auth_message("client_1", "update_both", challenge.challenge_id))
        with self.assertRaises(ChallengeRejected):
            store.verify_and_consume("client_1", "request_status", challenge.challenge_id, signature, token, NOW)

    def test_wrong_client_rejected(self) -> None:
        token = bytes.fromhex("00" * 32)
        store = ChallengeStore(random_bytes=lambda n: b"e" * n)
        challenge = store.issue("client_1", "update_both", NOW)
        signature = sign_message(token, canonical_auth_message("client_1", "update_both", challenge.challenge_id))
        with self.assertRaises(ChallengeRejected):
            store.verify_and_consume("client_2", "update_both", challenge.challenge_id, signature, token, NOW)

    def test_purge_expired(self) -> None:
        store = ChallengeStore(ttl=timedelta(seconds=10), random_bytes=lambda n: b"f" * n)
        store.issue("client_1", "update_both", NOW)
        self.assertEqual(len(store._challenges), 1)
        store.purge_expired(NOW + timedelta(seconds=11))
        self.assertEqual(len(store._challenges), 0)
