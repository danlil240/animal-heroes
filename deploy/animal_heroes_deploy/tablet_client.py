"""Pinned TLS tablet API client for the update protocol."""

from __future__ import annotations

import json
import socket
import ssl
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping

from deploy.animal_heroes_deploy.auth import canonical_auth_message, sign_message
from deploy.animal_heroes_deploy.discovery import DiscoveryAdvertisement


class TabletClientError(RuntimeError):
    """Raised when the tablet API client encounters an error."""


class TlsPinMismatch(TabletClientError):
    """Raised when the server certificate does not match the pinned fingerprint."""


class UpdateNotAvailable(TabletClientError):
    """Raised when no update is available."""


@dataclass(frozen=True)
class UpdateStatus:
    available: bool
    version_name: str | None = None
    version_code: int | None = None
    apk_sha256: str | None = None
    apk_size: int | None = None

    @classmethod
    def from_dict(cls, data: Mapping[str, object]) -> "UpdateStatus":
        return cls(
            available=bool(data.get("available", False)),
            version_name=data.get("version_name"),
            version_code=int(data["version_code"]) if "version_code" in data else None,
            apk_sha256=data.get("apk_sha256"),
            apk_size=int(data["apk_size"]) if "apk_size" in data else None,
        )


@dataclass(frozen=True)
class UpdateRequestResult:
    accepted: bool
    release_id: str | None = None
    version_name: str | None = None
    version_code: int | None = None
    apk_sha256: str | None = None


class PinnedTlsClient:
    def __init__(self, *, certificate_sha256: str, ca_cert_path: Path | None = None) -> None:
        self._pinned_sha256 = certificate_sha256
        self._ca_cert_path = ca_cert_path

    def request(
        self,
        *,
        host: str,
        port: int,
        method: str,
        path: str,
        body: bytes | None = None,
        headers: Mapping[str, str] | None = None,
        timeout_s: float = 10.0,
    ) -> tuple[int, bytes, Mapping[str, str]]:
        ctx = ssl.create_default_context(cafile=str(self._ca_cert_path) if self._ca_cert_path else None)
        if self._ca_cert_path is None:
            ctx.check_hostname = False
            ctx.verify_mode = ssl.CERT_NONE
        with socket.create_connection((host, port), timeout=timeout_s) as sock:
            with ctx.wrap_socket(sock, server_hostname=host) as tls:
                cert_der = tls.getpeercert(binary_form=True)
                if cert_der:
                    import hashlib
                    actual = hashlib.sha256(cert_der).hexdigest()
                    if actual != self._pinned_sha256:
                        raise TlsPinMismatch(f"certificate fingerprint mismatch: expected {self._pinned_sha256}, got {actual}")
                request_line = f"{method} {path} HTTP/1.1\r\nHost: {host}\r\nConnection: close\r\n"
                for key, value in (headers or {}).items():
                    request_line += f"{key}: {value}\r\n"
                if body is not None:
                    request_line += f"Content-Length: {len(body)}\r\n"
                request_line += "\r\n"
                tls.sendall(request_line.encode("ascii") + (body or b""))
                response = b""
                while True:
                    chunk = tls.recv(4096)
                    if not chunk:
                        break
                    response += chunk
        status, resp_body, resp_headers = _parse_http_response(response)
        return status, resp_body, resp_headers


def _parse_http_response(response: bytes) -> tuple[int, bytes, dict[str, str]]:
    header_end = response.find(b"\r\n\r\n")
    if header_end == -1:
        raise TabletClientError("malformed HTTP response")
    header_section = response[:header_end].decode("ascii", errors="replace")
    body = response[header_end + 4:]
    lines = header_section.split("\r\n")
    status_line = lines[0]
    parts = status_line.split(" ", 2)
    status = int(parts[1])
    headers: dict[str, str] = {}
    for line in lines[1:]:
        if ":" in line:
            key, _, value = line.partition(":")
            headers[key.strip()] = value.strip()
    return status, body, headers


class TabletUpdateClient:
    def __init__(self, *, tls_client: PinnedTlsClient, host: str, port: int, client_id: str, token: bytes) -> None:
        self._tls = tls_client
        self._host = host
        self._port = port
        self._client_id = client_id
        self._token = token

    def fetch_status(self) -> UpdateStatus:
        status, body, _ = self._tls.request(
            host=self._host,
            port=self._port,
            method="GET",
            path="/api/update/status",
        )
        if status != 200:
            raise TabletClientError(f"status request failed: {status}")
        return UpdateStatus.from_dict(json.loads(body.decode("utf-8")))

    def request_update(self, challenge_id: str) -> UpdateRequestResult:
        message = canonical_auth_message(self._client_id, "update_both", challenge_id)
        signature = sign_message(self._token, message)
        payload = json.dumps({
            "client_id": self._client_id,
            "action": "update_both",
            "challenge_id": challenge_id,
            "signature": signature,
        }).encode("utf-8")
        status, body, _ = self._tls.request(
            host=self._host,
            port=self._port,
            method="POST",
            path="/api/update/request",
            body=payload,
            headers={"Content-Type": "application/json"},
        )
        if status == 409:
            raise UpdateNotAvailable("no active release to deploy")
        if status != 202:
            raise TabletClientError(f"update request failed: {status}")
        data = json.loads(body.decode("utf-8"))
        return UpdateRequestResult(
            accepted=True,
            release_id=data.get("release_id"),
            version_name=data.get("version_name"),
            version_code=int(data["version_code"]) if "version_code" in data else None,
            apk_sha256=data.get("apk_sha256"),
        )
