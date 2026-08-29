"""UDP discovery responder for the tablet update API."""

from __future__ import annotations

import ipaddress
import json
import re
import socket
from dataclasses import dataclass
from typing import Mapping


_PROTOCOL_VERSION = 1
_MAX_PACKET_SIZE = 1024
_SERVICE_ID_RE = re.compile(r"^[A-Za-z0-9_-]{1,32}$")
_IPV4_RE = re.compile(
    r"^(?:(?:25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d)\.){3}(?:25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d)$"
)
_FINGERPRINT_RE = re.compile(r"^[0-9a-f]{64}$")
_NONCE_RE = re.compile(r"^[0-9a-f]{1,64}$")


class DiscoveryError(ValueError):
    """Raised when discovery advertisement data is invalid."""


@dataclass(frozen=True)
class DiscoveryAdvertisement:
    protocol_version: int
    service_id: str
    host: str
    port: int
    certificate_sha256: str
    pairing_nonce: str | None

    def to_bytes(self) -> bytes:
        data: dict[str, object] = {
            "protocol": self.protocol_version,
            "service_id": self.service_id,
            "host": self.host,
            "port": self.port,
            "certificate_sha256": self.certificate_sha256,
        }
        if self.pairing_nonce is not None:
            data["pairing_nonce"] = self.pairing_nonce
        packet = json.dumps(data, sort_keys=True).encode("ascii")
        if len(packet) > _MAX_PACKET_SIZE:
            raise DiscoveryError("advertisement exceeds 1024 bytes")
        return packet

    @classmethod
    def from_dict(cls, value: Mapping[str, object]) -> "DiscoveryAdvertisement":
        keys = set(value)
        required = {"protocol", "service_id", "host", "port", "certificate_sha256"}
        if not required.issubset(keys) or not keys.issubset(required | {"pairing_nonce"}):
            raise DiscoveryError("advertisement keys are invalid")
        protocol = int(value["protocol"])
        if protocol != _PROTOCOL_VERSION:
            raise DiscoveryError("protocol version mismatch")
        service_id = str(value["service_id"])
        if not _SERVICE_ID_RE.fullmatch(service_id):
            raise DiscoveryError("invalid service_id")
        host = str(value["host"])
        if not _IPV4_RE.fullmatch(host):
            raise DiscoveryError("invalid host address")
        try:
            addr = ipaddress.IPv4Address(host)
        except ipaddress.AddressValueError:
            raise DiscoveryError("invalid host address")
        if not addr.is_private or addr.is_loopback or addr.is_link_local:
            raise DiscoveryError("host must be a private LAN address")
        port = int(value["port"])
        if not (1 <= port <= 65535):
            raise DiscoveryError("invalid port")
        cert = str(value["certificate_sha256"])
        if not _FINGERPRINT_RE.fullmatch(cert):
            raise DiscoveryError("invalid certificate fingerprint")
        nonce = value.get("pairing_nonce")
        if nonce is not None:
            nonce = str(nonce)
            if not _NONCE_RE.fullmatch(nonce):
                raise DiscoveryError("invalid pairing nonce")
        return cls(
            protocol_version=protocol,
            service_id=service_id,
            host=host,
            port=port,
            certificate_sha256=cert,
            pairing_nonce=nonce,
        )


class UpdateDiscoveryResponder:
    def __init__(self, advertisement: DiscoveryAdvertisement) -> None:
        self._advertisement = advertisement
        self._socket: socket.socket | None = None

    def start(self, bind_address: str = "0.0.0.0", port: int = 0) -> tuple[str, int]:
        self._socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self._socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._socket.bind((bind_address, port))
        self._socket.settimeout(0.1)
        actual_host, actual_port = self._socket.getsockname()
        return actual_host, actual_port

    def tick(self) -> None:
        if self._socket is None:
            return
        try:
            data, addr = self._socket.recvfrom(_MAX_PACKET_SIZE)
        except socket.timeout:
            return
        self._socket.sendto(self._advertisement.to_bytes(), addr)

    def close(self) -> None:
        if self._socket is not None:
            self._socket.close()
            self._socket = None
