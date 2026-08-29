"""Launcher entry point for the Animal Heroes deployment service."""

from __future__ import annotations

import argparse
import json
import signal
import socket
import ssl
import sys
import threading
from http import HTTPStatus
from pathlib import Path
from typing import Any

from deploy.animal_heroes_deploy.audit import AuditLog
from deploy.animal_heroes_deploy.catalog import Catalog
from deploy.animal_heroes_deploy.config import DeployConfig
from deploy.animal_heroes_deploy.dashboard_routes import DashboardRoutes, LanApiRoutes
from deploy.animal_heroes_deploy.http_router import HttpRequest, HttpResponse, Router
from deploy.animal_heroes_deploy.paths import StatePaths
from deploy.animal_heroes_deploy.toolchain import Tool, Toolchain


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Animal Heroes local deployment service")
    parser.add_argument("--check", action="store_true", help="non-destructive local check and exit")
    parser.add_argument("--config", type=Path, help="path to deploy config JSON")
    parser.add_argument("--dashboard-port", type=int, help="override dashboard port")
    parser.add_argument("--lan-port", type=int, help="override LAN API port")
    args = parser.parse_args(argv)

    config_path = args.config or (Path("release/deploy_config.json"))
    if not config_path.exists():
        print(f"config not found: {config_path}", file=sys.stderr)
        return 2

    config = DeployConfig.from_dict(json.loads(config_path.read_text(encoding="utf-8")))
    paths = StatePaths.default()
    catalog = Catalog(paths)
    audit_log = AuditLog(paths)

    if args.check:
        return _run_check(config, catalog, paths)

    return _run_server(config, catalog, audit_log, paths, args)


def _run_check(config: DeployConfig, catalog: Catalog, paths: StatePaths) -> int:
    print("Configuration:")
    print(f"  package_id: {config.package_id}")
    print(f"  lan_address: {config.lan_address}")
    print(f"  lan_port: {config.lan_port}")
    print(f"  dashboard_port: {config.dashboard_port}")
    print(f"  devices: {len(config.devices)}")
    for device in config.devices:
        print(f"    {device.role.value}: {device.hardware_id[:6]}***")
    print(f"Catalog: {len(catalog.list_releases())} releases")
    active = catalog.active()
    if active:
        print(f"  active: {active.version_name} (code {active.version_code})")
    else:
        print("  active: none")
    print("Check: OK")
    return 0


def _run_server(
    config: DeployConfig,
    catalog: Catalog,
    audit_log: AuditLog,
    paths: StatePaths,
    args: argparse.Namespace,
) -> int:
    dashboard_port = args.dashboard_port or config.dashboard_port
    lan_port = args.lan_port or config.lan_port

    router = Router()
    DashboardRoutes(catalog, config).register(router)
    # LAN routes need a challenge verifier - stub for now
    def challenge_verifier(request: HttpRequest) -> HttpResponse:
        return HttpResponse.json(HTTPStatus.OK, {"ok": True})
    LanApiRoutes(catalog, config, challenge_verifier).register(router)

    # Loopback dashboard server
    dashboard_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    dashboard_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    dashboard_sock.bind(("127.0.0.1", dashboard_port))
    dashboard_sock.listen(5)
    dashboard_sock.settimeout(0.5)

    stop_event = threading.Event()

    def handle_signal(signum, frame):
        stop_event.set()

    signal.signal(signal.SIGINT, handle_signal)
    signal.signal(signal.SIGTERM, handle_signal)

    print(f"Dashboard listening on http://127.0.0.1:{dashboard_port}")
    print(f"LAN API would bind to {config.lan_address}:{lan_port}")
    print("Press Ctrl+C to stop")

    try:
        while not stop_event.is_set():
            try:
                conn, addr = dashboard_sock.accept()
            except socket.timeout:
                continue
            try:
                _handle_connection(conn, addr, router)
            except Exception:
                pass
            finally:
                conn.close()
    finally:
        dashboard_sock.close()
        print("Stopped")
    return 0


def _handle_connection(conn: socket.socket, addr: tuple[str, int], router: Router) -> None:
    conn.settimeout(5.0)
    data = b""
    while b"\r\n\r\n" not in data:
        chunk = conn.recv(4096)
        if not chunk:
            return
        data += chunk
    header_end = data.find(b"\r\n\r\n")
    header_section = data[:header_end].decode("ascii", errors="replace")
    lines = header_section.split("\r\n")
    request_line = lines[0]
    parts = request_line.split(" ")
    if len(parts) < 2:
        return
    method, path = parts[0], parts[1]
    headers: dict[str, str] = {}
    for line in lines[1:]:
        if ":" in line:
            key, _, value = line.partition(":")
            headers[key.strip()] = value.strip()
    body = data[header_end + 4:]
    content_length = int(headers.get("Content-Length", "0"))
    while len(body) < content_length:
        chunk = conn.recv(4096)
        if not chunk:
            break
        body += chunk
    request = HttpRequest(
        method=method,
        path=path,
        headers=headers,
        body=body,
        peer=addr[0],
    )
    response = router.dispatch(request)
    response_bytes = f"HTTP/1.1 {response.status} OK\r\n".encode("ascii")
    for key, value in response.headers.items():
        response_bytes += f"{key}: {value}\r\n".encode("ascii")
    response_bytes += f"Content-Length: {len(response.body)}\r\n".encode("ascii")
    response_bytes += b"Connection: close\r\n\r\n"
    response_bytes += response.body
    conn.sendall(response_bytes)


if __name__ == "__main__":
    sys.exit(main())
