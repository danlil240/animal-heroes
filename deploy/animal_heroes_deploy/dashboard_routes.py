"""Dashboard and LAN API route handlers."""

from __future__ import annotations

from dataclasses import dataclass
from http import HTTPStatus
from typing import Callable

from deploy.animal_heroes_deploy.catalog import Catalog
from deploy.animal_heroes_deploy.config import DeployConfig
from deploy.animal_heroes_deploy.deployment import DeploymentCoordinator, DeploymentState
from deploy.animal_heroes_deploy.domain import ReleaseRecord
from deploy.animal_heroes_deploy.http_router import (
    HttpRequest,
    HttpResponse,
    Router,
    require_json_fields,
)


@dataclass(frozen=True)
class DashboardRoutes:
    catalog: Catalog
    config: DeployConfig

    def register(self, router: Router) -> None:
        router.add_local("GET", "/health", self.health)
        router.add_local("GET", "/api/releases", self.list_releases)
        router.add_local("GET", "/api/active", self.active_release)
        router.add_local("GET", "/api/config", self.config_info)

    def health(self, request: HttpRequest) -> HttpResponse:
        return HttpResponse.json(HTTPStatus.OK, {"status": "ok"})

    def list_releases(self, request: HttpRequest) -> HttpResponse:
        releases = self.catalog.list_releases()
        return HttpResponse.json(HTTPStatus.OK, {
            "releases": [
                {
                    "release_id": r.release_id,
                    "version_name": r.version_name,
                    "version_code": r.version_code,
                    "channel": r.channel.value,
                    "built_at": r.built_at,
                }
                for r in releases
            ]
        })

    def active_release(self, request: HttpRequest) -> HttpResponse:
        active = self.catalog.active()
        if active is None:
            return HttpResponse.json(HTTPStatus.OK, {"active": None})
        return HttpResponse.json(HTTPStatus.OK, {
            "active": {
                "release_id": active.release_id,
                "version_name": active.version_name,
                "version_code": active.version_code,
                "channel": active.channel.value,
                "apk_sha256": active.apk_sha256,
                "apk_size": active.apk_size,
            }
        })

    def config_info(self, request: HttpRequest) -> HttpResponse:
        return HttpResponse.json(HTTPStatus.OK, {
            "package_id": self.config.package_id,
            "lan_address": self.config.lan_address,
            "lan_port": self.config.lan_port,
            "dashboard_port": self.config.dashboard_port,
            "devices": [
                {"role": d.role.value, "hardware_id": d.hardware_id[:6] + "***"}
                for d in self.config.devices
            ],
        })


@dataclass(frozen=True)
class LanApiRoutes:
    catalog: Catalog
    config: DeployConfig
    challenge_verifier: Callable[[HttpRequest], HttpResponse]

    def register(self, router: Router) -> None:
        router.add_lan("GET", "/api/update/status", self.update_status)
        router.add_lan("POST", "/api/update/request", self.request_update)

    def update_status(self, request: HttpRequest) -> HttpResponse:
        active = self.catalog.active()
        if active is None:
            return HttpResponse.json(HTTPStatus.OK, {"available": False})
        return HttpResponse.json(HTTPStatus.OK, {
            "available": True,
            "version_name": active.version_name,
            "version_code": active.version_code,
            "apk_sha256": active.apk_sha256,
            "apk_size": active.apk_size,
        })

    @require_json_fields("client_id", "action", "challenge_id", "signature")
    def request_update(self, request: HttpRequest) -> HttpResponse:
        auth_response = self.challenge_verifier(request)
        if auth_response.status != HTTPStatus.OK:
            return auth_response
        active = self.catalog.active()
        if active is None:
            return HttpResponse.json(HTTPStatus.CONFLICT, {"error": "no active release"})
        return HttpResponse.json(HTTPStatus.ACCEPTED, {
            "release_id": active.release_id,
            "version_name": active.version_name,
            "version_code": active.version_code,
            "apk_sha256": active.apk_sha256,
        })
