"""One-use, time-limited application pairing sessions."""

from __future__ import annotations

import secrets
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Callable

from deploy.animal_heroes_deploy.auth import SAFE_TOKEN, pairing_code
from deploy.animal_heroes_deploy.domain import DeviceRole


PAIRING_TTL = timedelta(minutes=5)


class PairingError(ValueError):
    """Raised when a pairing operation is invalid."""


class PairingSessionNotOpen(PairingError):
    """Raised when no pairing session is open."""


class PairingSessionExpired(PairingError):
    """Raised when a pairing session has expired."""


class PairingAlreadyUsed(PairingError):
    """Raised when a pairing session has already been consumed."""


@dataclass(frozen=True)
class PairingSession:
    nonce: str
    certificate_sha256: str
    opened_at: datetime
    expires_at: datetime
    intended_role: DeviceRole
    intended_hardware_id: str


@dataclass(frozen=True)
class PairingResult:
    token: bytes
    client_id: str
    role: DeviceRole
    hardware_id: str


class PairingManager:
    def __init__(
        self,
        *,
        ttl: timedelta = PAIRING_TTL,
        random_bytes: Callable[[int], bytes] | None = None,
    ) -> None:
        self._ttl = ttl
        self._random_bytes = random_bytes or secrets.token_bytes
        self._session: PairingSession | None = None
        self._used = False

    def open(
        self,
        *,
        certificate_sha256: str,
        intended_role: DeviceRole,
        intended_hardware_id: str,
        now: datetime,
    ) -> PairingSession:
        nonce = self._random_bytes(16).hex()
        session = PairingSession(
            nonce=nonce,
            certificate_sha256=certificate_sha256,
            opened_at=now,
            expires_at=now + self._ttl,
            intended_role=intended_role,
            intended_hardware_id=intended_hardware_id,
        )
        self._session = session
        self._used = False
        return session

    def is_open(self, now: datetime) -> bool:
        if self._session is None:
            return False
        if now > self._session.expires_at:
            return False
        return not self._used

    def code(self) -> str:
        if self._session is None:
            raise PairingSessionNotOpen("no pairing session is open")
        return pairing_code(self._session.certificate_sha256, self._session.nonce)

    def accept(
        self,
        *,
        entered_code: str,
        client_id: str,
        observed_certificate_sha256: str,
        hardware_id: str,
        now: datetime,
    ) -> PairingResult:
        if self._session is None:
            raise PairingSessionNotOpen("no pairing session is open")
        if self._used:
            raise PairingAlreadyUsed("pairing session already consumed")
        if now > self._session.expires_at:
            raise PairingSessionExpired("pairing session expired")
        if not SAFE_TOKEN.fullmatch(client_id):
            raise PairingError("invalid client_id")
        if observed_certificate_sha256 != self._session.certificate_sha256:
            raise PairingError("certificate fingerprint mismatch")
        if hardware_id != self._session.intended_hardware_id:
            raise PairingError("hardware identity mismatch")
        expected_code = self.code()
        if not _constant_time_eq(entered_code, expected_code):
            raise PairingError("pairing code mismatch")
        token = self._random_bytes(32)
        self._used = True
        return PairingResult(
            token=token,
            client_id=client_id,
            role=self._session.intended_role,
            hardware_id=hardware_id,
        )

    def revoke(self) -> None:
        self._session = None
        self._used = False


def _constant_time_eq(a: str, b: str) -> bool:
    import hmac
    return hmac.compare_digest(a, b)
