"""Validated XDG state paths and path-containment guards."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping


APP_DIR = "animal-heroes-deploy"


class PathBoundaryError(ValueError):
    """Raised when a candidate path escapes the required base directory."""


@dataclass(frozen=True)
class StatePaths:
    config: Path
    data: Path
    runtime: Path

    @classmethod
    def resolve(cls, env: Mapping[str, str], uid: int) -> "StatePaths":
        home = Path(env["HOME"]).resolve(strict=True)
        config = Path(env.get("XDG_CONFIG_HOME", str(home / ".config"))) / APP_DIR
        data = Path(env.get("XDG_DATA_HOME", str(home / ".local/share"))) / APP_DIR
        if env.get("XDG_RUNTIME_DIR"):
            runtime_root = Path(env["XDG_RUNTIME_DIR"])
        else:
            runtime_root = Path(env.get("TMPDIR", "/tmp")) / f"animal-heroes-deploy-{uid}"
        return cls(
            config.resolve(strict=False),
            data.resolve(strict=False),
            (runtime_root / APP_DIR).resolve(strict=False),
        )

    @classmethod
    def default(cls) -> "StatePaths":
        import os as _os
        return cls.resolve(dict(_os.environ), _os.getuid())

    @classmethod
    def for_test(cls, root: Path) -> "StatePaths":
        root = root.resolve(strict=False)
        return cls(
            root / "config",
            root / "data",
            root / "runtime",
        )

    def ensure(self) -> None:
        for path in (self.config, self.data, self.runtime):
            path.mkdir(parents=True, exist_ok=True)
            os.chmod(path, 0o700)

    @property
    def catalog_dir(self) -> Path:
        return self.data / "catalog"

    @property
    def apk_dir(self) -> Path:
        return self.catalog_dir / "apks"

    @property
    def metadata_dir(self) -> Path:
        return self.catalog_dir / "metadata"

    @property
    def deployments_dir(self) -> Path:
        return self.catalog_dir / "deployments"

    @property
    def catalog_index_path(self) -> Path:
        return self.catalog_dir / "catalog.json"

    @property
    def active_pointer_path(self) -> Path:
        return self.catalog_dir / "active.json"

    @property
    def config_file_path(self) -> Path:
        return self.config / "config.json"

    @property
    def audit_log_path(self) -> Path:
        return self.data / "audit.jsonl"

    @property
    def lock_path(self) -> Path:
        return self.runtime / "deploy.lock"


def require_child(base: Path, candidate: Path) -> Path:
    resolved_base = base.resolve(strict=False)
    resolved_candidate = candidate.resolve(strict=False)
    if resolved_candidate == resolved_base or not resolved_candidate.is_relative_to(resolved_base):
        raise PathBoundaryError("path is outside the application state directory")
    return resolved_candidate
