"""Authentication primitives: canonical messages, HMAC, and challenge store."""

from __future__ import annotations

import base64
import hashlib
import hmac
import re
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Callable, Mapping

SAFE_TOKEN = re.compile(r"^[A-Za-z0-9_-]{1,64}$")


class AuthenticationError(ValueError):
    """Raised when an authentication field or challenge is invalid."""


class ChallengeRejected(AuthenticationError):
    """Raised when a challenge is expired, replayed, or mismatched."""


def canonical_auth_message(client_id: str, action: str, challenge: str) -> bytes:
    for value in (client_id, action, challenge):
        if not isinstance(value, str) or SAFE_TOKEN.fullmatch(value) is None:
            raise AuthenticationError("invalid authentication field")
    return f"animal-heroes-update-v1\n{client_id}\n{action}\n{challenge}\n".encode("ascii")


def sign_message(token: bytes, message: bytes) -> str:
    if not isinstance(token, (bytes, bytearray)) or len(token) != 32:
        raise AuthenticationError("token must be 32 bytes")
    digest = hmac.digest(bytes(token), message, "sha256")
    return base64.b64encode(digest).decode("ascii")


def pairing_code(certificate_sha256: str, nonce: str) -> str:
    if not re.fullmatch(r"[0-9a-f]{64}", certificate_sha256):
        raise AuthenticationError("certificate_sha256 must be 64 hex characters")
    if not SAFE_TOKEN.fullmatch(nonce):
        raise AuthenticationError("invalid pairing nonce")
    digest = hashlib.sha256(
        f"animal-heroes-pair-v1\n{certificate_sha256}\n{nonce}\n".encode("ascii")
    ).digest()
    return f"{int.from_bytes(digest[:4], 'big') % 1_000_000:06d}"


@dataclass(frozen=True)
class Challenge:
    challenge_id: str
    client_id: str
    action: str
    issued_at: datetime
    expires_at: datetime


class ChallengeStore:
    def __init__(
        self,
        *,
        ttl: timedelta = timedelta(seconds=30),
        random_bytes: Callable[[int], bytes] | None = None,
    ) -> None:
        self._ttl = ttl
        self._random_bytes = random_bytes or __import__("secrets").token_bytes
        self._challenges: dict[str, Challenge] = {}

    def issue(self, client_id: str, action: str, now: datetime) -> Challenge:
        if not SAFE_TOKEN.fullmatch(client_id):
            raise AuthenticationError("invalid client_id")
        if not SAFE_TOKEN.fullmatch(action):
            raise AuthenticationError("invalid action")
        challenge_id = self._random_bytes(16).hex()
        expires = now + self._ttl
        challenge = Challenge(
            challenge_id=challenge_id,
            client_id=client_id,
            action=action,
            issued_at=now,
            expires_at=expires,
        )
        self._challenges[challenge_id] = challenge
        return challenge

    def verify_and_consume(
        self,
        client_id: str,
        action: str,
        challenge_id: str,
        signature: str,
        token: bytes,
        now: datetime,
    ) -> None:
        challenge = self._challenges.get(challenge_id)
        if challenge is None:
            raise ChallengeRejected("unknown or already-consumed challenge")
        del self._challenges[challenge_id]
        if now > challenge.expires_at:
            raise ChallengeRejected("challenge expired")
        if challenge.client_id != client_id or challenge.action != action:
            raise ChallengeRejected("challenge does not match client or action")
        message = canonical_auth_message(client_id, action, challenge_id)
        expected = sign_message(token, message)
        if not hmac.compare_digest(expected, signature):
            raise ChallengeRejected("signature mismatch")

    def purge_expired(self, now: datetime) -> None:
        expired = [cid for cid, ch in self._challenges.items() if now > ch.expires_at]
        for cid in expired:
            del self._challenges[cid]
