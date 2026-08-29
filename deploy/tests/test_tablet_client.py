import json
import ssl
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

from deploy.animal_heroes_deploy.auth import canonical_auth_message, sign_message
from deploy.animal_heroes_deploy.tablet_client import (
    PinnedTlsClient,
    TabletClientError,
    TabletUpdateClient,
    TlsPinMismatch,
    UpdateNotAvailable,
    UpdateRequestResult,
    UpdateStatus,
    _parse_http_response,
)


CERT_SHA = "a" * 64
TOKEN = bytes.fromhex("00" * 32)


class ParseHttpResponseTests(unittest.TestCase):
    def test_parses_simple_response(self) -> None:
        response = b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"ok\": true}"
        status, body, headers = _parse_http_response(response)
        self.assertEqual(status, 200)
        self.assertEqual(body, b"{\"ok\": true}")
        self.assertEqual(headers["Content-Type"], "application/json")


class UpdateStatusTests(unittest.TestCase):
    def test_no_update(self) -> None:
        status = UpdateStatus.from_dict({"available": False})
        self.assertFalse(status.available)
        self.assertIsNone(status.version_name)

    def test_with_update(self) -> None:
        status = UpdateStatus.from_dict({
            "available": True,
            "version_name": "1.0.0-rc.1",
            "version_code": 2,
            "apk_sha256": "abc",
            "apk_size": 1024,
        })
        self.assertTrue(status.available)
        self.assertEqual(status.version_code, 2)
        self.assertEqual(status.apk_sha256, "abc")


class PinnedTlsClientTests(unittest.TestCase):
    def test_pin_mismatch_raises(self) -> None:
        client = PinnedTlsClient(certificate_sha256="b" * 64)
        mock_tls = MagicMock()
        mock_tls.getpeercert.return_value = b"fake-cert-der"
        with patch("socket.create_connection"), patch("ssl.create_default_context") as ctx_fn:
            ctx = MagicMock()
            ctx_fn.return_value = ctx
            ctx.wrap_socket.return_value.__enter__.return_value = mock_tls
            with self.assertRaises(TlsPinMismatch):
                client.request(host="192.168.1.5", port=8443, method="GET", path="/test")

    def test_successful_request(self) -> None:
        client = PinnedTlsClient(certificate_sha256=CERT_SHA)
        mock_tls = MagicMock()
        mock_tls.getpeercert.return_value = b""  # Empty cert, no pinning check
        mock_tls.recv.side_effect = [b"HTTP/1.1 200 OK\r\n\r\nbody", b""]
        with patch("socket.create_connection"), patch("ssl.create_default_context") as ctx_fn:
            ctx = MagicMock()
            ctx_fn.return_value = ctx
            ctx.wrap_socket.return_value.__enter__.return_value = mock_tls
            status, body, _ = client.request(host="192.168.1.5", port=8443, method="GET", path="/test")
            self.assertEqual(status, 200)
            self.assertEqual(body, b"body")


class TabletUpdateClientTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tls = MagicMock(spec=PinnedTlsClient)
        self.client = TabletUpdateClient(
            tls_client=self.tls,
            host="192.168.1.5",
            port=8443,
            client_id="client_1",
            token=TOKEN,
        )

    def test_fetch_status_returns_update(self) -> None:
        self.tls.request.return_value = (200, json.dumps({
            "available": True,
            "version_name": "1.0.0-rc.1",
            "version_code": 2,
            "apk_sha256": "abc",
            "apk_size": 1024,
        }).encode(), {})
        status = self.client.fetch_status()
        self.assertTrue(status.available)
        self.assertEqual(status.version_code, 2)

    def test_fetch_status_no_update(self) -> None:
        self.tls.request.return_value = (200, json.dumps({"available": False}).encode(), {})
        status = self.client.fetch_status()
        self.assertFalse(status.available)

    def test_request_update_succeeds(self) -> None:
        self.tls.request.return_value = (202, json.dumps({
            "release_id": "0000000002-1.0.0-rc.1",
            "version_name": "1.0.0-rc.1",
            "version_code": 2,
            "apk_sha256": "abc",
        }).encode(), {})
        result = self.client.request_update("challenge_1")
        self.assertTrue(result.accepted)
        self.assertEqual(result.version_code, 2)
        # Verify the signature in the payload
        call_args = self.tls.request.call_args
        payload = json.loads(call_args.kwargs["body"].decode())
        expected_sig = sign_message(TOKEN, canonical_auth_message("client_1", "update_both", "challenge_1"))
        self.assertEqual(payload["signature"], expected_sig)

    def test_request_update_no_active_raises(self) -> None:
        self.tls.request.return_value = (409, b'{"error": "no active release"}', {})
        with self.assertRaises(UpdateNotAvailable):
            self.client.request_update("challenge_1")

    def test_request_update_failure_raises(self) -> None:
        self.tls.request.return_value = (500, b'{"error": "server error"}', {})
        with self.assertRaises(TabletClientError):
            self.client.request_update("challenge_1")
