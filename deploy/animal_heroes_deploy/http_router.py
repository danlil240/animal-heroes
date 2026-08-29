"""HTTP request routing for split local dashboard and LAN tablet APIs."""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from http import HTTPStatus
from typing import Callable, Mapping, Sequence


class RouteError(ValueError):
    """Raised when a route definition is invalid."""


@dataclass(frozen=True)
class HttpRequest:
    method: str
    path: str
    headers: Mapping[str, str] = field(default_factory=dict)
    body: bytes = b""
    peer: str = ""

    @property
    def is_loopback(self) -> bool:
        return self.peer.startswith("127.")

    @property
    def is_private_lan(self) -> bool:
        if self.is_loopback:
            return False
        parts = self.peer.split(".")
        if len(parts) != 4:
            return False
        try:
            octets = [int(p) for p in parts]
        except ValueError:
            return False
        if octets[0] == 10:
            return True
        if octets[0] == 172 and 16 <= octets[1] <= 31:
            return True
        if octets[0] == 192 and octets[1] == 168:
            return True
        return False

    def json_body(self) -> object:
        return json.loads(self.body.decode("utf-8"))


@dataclass(frozen=True)
class HttpResponse:
    status: int
    body: bytes = b""
    headers: Mapping[str, str] = field(default_factory=dict)

    @classmethod
    def json(cls, status: int, data: object) -> "HttpResponse":
        return cls(status=status, body=json.dumps(data).encode("utf-8"), headers={"Content-Type": "application/json"})

    @classmethod
    def text(cls, status: int, data: str) -> "HttpResponse":
        return cls(status=status, body=data.encode("utf-8"), headers={"Content-Type": "text/plain; charset=utf-8"})


Handler = Callable[[HttpRequest], HttpResponse]


class Route:
    def __init__(self, method: str, pattern: str, handler: Handler, *, local_only: bool = False, lan_only: bool = False) -> None:
        if local_only and lan_only:
            raise RouteError("route cannot be both local-only and lan-only")
        self.method = method.upper()
        self.pattern = re.compile(f"^{pattern}$")
        self.handler = handler
        self.local_only = local_only
        self.lan_only = lan_only

    def matches(self, request: HttpRequest) -> bool:
        if self.method != "*" and request.method != self.method:
            return False
        return self.pattern.match(request.path) is not None


class Router:
    def __init__(self) -> None:
        self._routes: list[Route] = []

    def add(self, route: Route) -> None:
        self._routes.append(route)

    def add_local(self, method: str, pattern: str, handler: Handler) -> None:
        self.add(Route(method, pattern, handler, local_only=True))

    def add_lan(self, method: str, pattern: str, handler: Handler) -> None:
        self.add(Route(method, pattern, handler, lan_only=True))

    def add_shared(self, method: str, pattern: str, handler: Handler) -> None:
        self.add(Route(method, pattern, handler))

    def dispatch(self, request: HttpRequest) -> HttpResponse:
        for route in self._routes:
            if not route.matches(request):
                continue
            if route.local_only and not request.is_loopback:
                return HttpResponse.text(HTTPStatus.FORBIDDEN, "loopback only")
            if route.lan_only and not request.is_private_lan:
                return HttpResponse.text(HTTPStatus.FORBIDDEN, "LAN only")
            return route.handler(request)
        return HttpResponse.text(HTTPStatus.NOT_FOUND, "not found")


def require_json_fields(*required: str) -> Callable[[Handler], Handler]:
    def decorator(handler: Handler) -> Handler:
        def wrapper(*args, **kwargs) -> HttpResponse:
            request = args[-1] if args else kwargs.get("request")
            if request is None:
                return handler(*args, **kwargs)
            try:
                data = request.json_body()
            except (json.JSONDecodeError, UnicodeDecodeError):
                return HttpResponse.json(HTTPStatus.BAD_REQUEST, {"error": "invalid JSON"})
            if not isinstance(data, dict):
                return HttpResponse.json(HTTPStatus.BAD_REQUEST, {"error": "expected JSON object"})
            missing = [field for field in required if field not in data]
            if missing:
                return HttpResponse.json(HTTPStatus.BAD_REQUEST, {"error": f"missing fields: {missing}"})
            return handler(*args, **kwargs)
        return wrapper
    return decorator
