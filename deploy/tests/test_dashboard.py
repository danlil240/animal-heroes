import json
import unittest
from http import HTTPStatus
from unittest.mock import MagicMock

from deploy.animal_heroes_deploy.catalog import Catalog
from deploy.animal_heroes_deploy.config import DeployConfig
from deploy.animal_heroes_deploy.dashboard_routes import DashboardRoutes, LanApiRoutes
from deploy.animal_heroes_deploy.domain import ReleaseChannel, ReleaseRecord
from deploy.animal_heroes_deploy.http_router import HttpRequest, HttpResponse, Router, RouteError
from deploy.animal_heroes_deploy.paths import StatePaths
import hashlib
import tempfile
from pathlib import Path


def valid_config_dict(tmp: Path) -> dict[str, object]:
    keystore = tmp / "release.keystore"
    keystore.write_bytes(b"dummy")
    return {
        "package_id": "org.danlil.animalheroes",
        "lan_address": "192.168.1.100",
        "lan_port": 8443,
        "dashboard_port": 8442,
        "discovery_port": 28742,
        "keystore_path": str(keystore),
        "keystore_alias": "animalheroes",
        "pinned_signer_sha256": "a" * 64,
        "devices": [
            {"role": "host", "hardware_id": "R28M30ABCDEF"},
            {"role": "client", "hardware_id": "R28M30GHIJKL"},
        ],
        "retention": "retain_all",
    }


class HttpRequestTests(unittest.TestCase):
    def test_loopback_detection(self) -> None:
        self.assertTrue(HttpRequest("GET", "/", peer="127.0.0.1").is_loopback)
        self.assertFalse(HttpRequest("GET", "/", peer="192.168.1.5").is_loopback)

    def test_private_lan_detection(self) -> None:
        for addr in ("10.0.0.1", "172.16.0.1", "172.31.255.255", "192.168.1.5"):
            self.assertTrue(HttpRequest("GET", "/", peer=addr).is_private_lan, addr)
        for addr in ("127.0.0.1", "8.8.8.8", "172.32.0.1", "0.0.0.0"):
            self.assertFalse(HttpRequest("GET", "/", peer=addr).is_private_lan, addr)


class RouterBoundaryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.router = Router()
        self.router.add_local("GET", "/local", lambda r: HttpResponse.text(200, "local"))
        self.router.add_lan("GET", "/lan", lambda r: HttpResponse.text(200, "lan"))
        self.router.add_shared("GET", "/shared", lambda r: HttpResponse.text(200, "shared"))

    def test_local_route_rejects_lan_peer(self) -> None:
        response = self.router.dispatch(HttpRequest("GET", "/local", peer="192.168.1.5"))
        self.assertEqual(response.status, HTTPStatus.FORBIDDEN)

    def test_local_route_accepts_loopback(self) -> None:
        response = self.router.dispatch(HttpRequest("GET", "/local", peer="127.0.0.1"))
        self.assertEqual(response.status, 200)
        self.assertEqual(response.body, b"local")

    def test_lan_route_rejects_loopback(self) -> None:
        response = self.router.dispatch(HttpRequest("GET", "/lan", peer="127.0.0.1"))
        self.assertEqual(response.status, HTTPStatus.FORBIDDEN)

    def test_lan_route_accepts_private_lan(self) -> None:
        response = self.router.dispatch(HttpRequest("GET", "/lan", peer="192.168.1.5"))
        self.assertEqual(response.status, 200)

    def test_lan_route_rejects_public(self) -> None:
        response = self.router.dispatch(HttpRequest("GET", "/lan", peer="8.8.8.8"))
        self.assertEqual(response.status, HTTPStatus.FORBIDDEN)

    def test_shared_route_accepts_both(self) -> None:
        self.assertEqual(self.router.dispatch(HttpRequest("GET", "/shared", peer="127.0.0.1")).status, 200)
        self.assertEqual(self.router.dispatch(HttpRequest("GET", "/shared", peer="192.168.1.5")).status, 200)

    def test_unknown_route_returns_404(self) -> None:
        response = self.router.dispatch(HttpRequest("GET", "/unknown", peer="127.0.0.1"))
        self.assertEqual(response.status, HTTPStatus.NOT_FOUND)

    def test_method_mismatch_returns_404(self) -> None:
        response = self.router.dispatch(HttpRequest("POST", "/local", peer="127.0.0.1"))
        self.assertEqual(response.status, HTTPStatus.NOT_FOUND)

    def test_cannot_be_both_local_and_lan(self) -> None:
        with self.assertRaises(RouteError):
            from deploy.animal_heroes_deploy.http_router import Route
            Route("GET", "/both", lambda r: HttpResponse.text(200, "both"), local_only=True, lan_only=True)


class DashboardRoutesTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmpdir = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmpdir.cleanup)
        self.tmp = Path(self._tmpdir.name)
        self.paths = StatePaths.for_test(self.tmp)
        self.config = DeployConfig.from_dict(valid_config_dict(self.tmp))
        self.catalog = Catalog(self.paths)
        self.router = Router()
        DashboardRoutes(self.catalog, self.config).register(self.router)

    def test_health(self) -> None:
        response = self.router.dispatch(HttpRequest("GET", "/health", peer="127.0.0.1"))
        self.assertEqual(response.status, 200)
        self.assertEqual(json.loads(response.body)["status"], "ok")

    def test_health_rejects_lan(self) -> None:
        response = self.router.dispatch(HttpRequest("GET", "/health", peer="192.168.1.5"))
        self.assertEqual(response.status, HTTPStatus.FORBIDDEN)

    def test_list_releases_empty(self) -> None:
        response = self.router.dispatch(HttpRequest("GET", "/api/releases", peer="127.0.0.1"))
        self.assertEqual(response.status, 200)
        self.assertEqual(json.loads(response.body)["releases"], [])

    def test_config_info_redacts_hardware_id(self) -> None:
        response = self.router.dispatch(HttpRequest("GET", "/api/config", peer="127.0.0.1"))
        data = json.loads(response.body)
        for device in data["devices"]:
            self.assertIn("***", device["hardware_id"])


class LanApiRoutesTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmpdir = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmpdir.cleanup)
        self.tmp = Path(self._tmpdir.name)
        self.paths = StatePaths.for_test(self.tmp)
        self.config = DeployConfig.from_dict(valid_config_dict(self.tmp))
        self.catalog = Catalog(self.paths)
        self.verifier = MagicMock(return_value=HttpResponse.json(200, {"ok": True}))
        self.router = Router()
        LanApiRoutes(self.catalog, self.config, self.verifier).register(self.router)

    def test_update_status_no_active(self) -> None:
        response = self.router.dispatch(HttpRequest("GET", "/api/update/status", peer="192.168.1.5"))
        self.assertEqual(response.status, 200)
        self.assertFalse(json.loads(response.body)["available"])

    def test_update_status_rejects_loopback(self) -> None:
        response = self.router.dispatch(HttpRequest("GET", "/api/update/status", peer="127.0.0.1"))
        self.assertEqual(response.status, HTTPStatus.FORBIDDEN)

    def test_request_update_rejects_loopback(self) -> None:
        response = self.router.dispatch(HttpRequest("POST", "/api/update/request", peer="127.0.0.1"))
        self.assertEqual(response.status, HTTPStatus.FORBIDDEN)

    def test_request_update_requires_json_fields(self) -> None:
        response = self.router.dispatch(
            HttpRequest("POST", "/api/update/request", peer="192.168.1.5", body=b"{}")
        )
        self.assertEqual(response.status, HTTPStatus.BAD_REQUEST)

    def test_request_update_rejects_invalid_json(self) -> None:
        response = self.router.dispatch(
            HttpRequest("POST", "/api/update/request", peer="192.168.1.5", body=b"not json")
        )
        self.assertEqual(response.status, HTTPStatus.BAD_REQUEST)

    def test_request_update_passes_auth_to_verifier(self) -> None:
        body = json.dumps({
            "client_id": "client_1",
            "action": "update_both",
            "challenge_id": "abc123",
            "signature": "sig",
        }).encode()
        # No active release
        response = self.router.dispatch(
            HttpRequest("POST", "/api/update/request", peer="192.168.1.5", body=body)
        )
        self.assertEqual(response.status, HTTPStatus.CONFLICT)
        self.verifier.assert_called_once()
