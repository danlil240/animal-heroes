"""Immutable release catalog with atomic publication and compare-and-swap active pointer."""

from __future__ import annotations

import json
import os
import tempfile
from dataclasses import dataclass
from pathlib import Path

from deploy.animal_heroes_deploy.domain import DeploymentRecord, ReleaseRecord
from deploy.animal_heroes_deploy.paths import StatePaths, require_child


class ReleaseExistsError(ValueError):
    """Raised when a release ID is already published."""


class StaleCatalogRevision(ValueError):
    """Raised when the catalog revision changed before a compare-and-swap."""


class ReleaseNotFoundError(KeyError):
    """Raised when a release ID is not in the catalog."""


@dataclass(frozen=True)
class CatalogIndex:
    revision: int
    release_ids: tuple[str, ...]

    @classmethod
    def from_dict(cls, value: dict[str, object]) -> "CatalogIndex":
        return cls(
            revision=int(value.get("revision", 0)),
            release_ids=tuple(str(r) for r in value.get("releases", [])),
        )

    def to_dict(self) -> dict[str, object]:
        return {"revision": self.revision, "releases": list(self.release_ids)}


class Catalog:
    def __init__(self, paths: StatePaths) -> None:
        self._paths = paths
        self._paths.ensure()
        for sub in (self._paths.catalog_dir, self._paths.apk_dir, self._paths.metadata_dir, self._paths.deployments_dir):
            sub.mkdir(parents=True, exist_ok=True)
            os.chmod(sub, 0o700)

    def revision(self) -> int:
        return self._load_index().revision

    def list_releases(self) -> tuple[ReleaseRecord, ...]:
        index = self._load_index()
        return tuple(self._load_record(rid) for rid in index.release_ids)

    def get(self, release_id: str) -> ReleaseRecord | None:
        index = self._load_index()
        if release_id not in index.release_ids:
            return None
        return self._load_record(release_id)

    def active(self) -> ReleaseRecord | None:
        path = self._paths.active_pointer_path
        if not path.exists():
            return None
        data = json.loads(path.read_text(encoding="utf-8"))
        release_id = str(data["release_id"])
        return self.get(release_id)

    def set_active(self, release_id: str, *, expected_revision: int) -> None:
        index = self._load_index()
        if index.revision != expected_revision:
            raise StaleCatalogRevision(
                f"catalog revision {index.revision} != expected {expected_revision}"
            )
        if release_id not in index.release_ids:
            raise ReleaseNotFoundError(release_id)
        self._write_active(release_id)

    def publish(self, source_apk: Path, release: ReleaseRecord) -> ReleaseRecord:
        index = self._load_index()
        if release.release_id in index.release_ids:
            raise ReleaseExistsError(release.release_id)
        if release.version_code <= 0:
            raise ValueError("version_code must be a positive integer")
        existing_codes = [self._load_record(rid).version_code for rid in index.release_ids]
        if existing_codes and release.version_code <= max(existing_codes):
            raise ValueError(
                f"version_code {release.version_code} must exceed catalog maximum {max(existing_codes)}"
            )
        dest_apk = self._paths.apk_dir / f"{release.release_id}.apk"
        dest_meta = self._paths.metadata_dir / f"{release.release_id}.json"
        _atomic_copy(source_apk, dest_apk, readonly=True)
        _atomic_write(dest_meta, json.dumps(release.to_dict(), indent=2, sort_keys=True), readonly=True)
        new_ids = (*index.release_ids, release.release_id)
        new_index = CatalogIndex(revision=index.revision + 1, release_ids=new_ids)
        self._write_index(new_index)
        if self.active() is None:
            self._write_active(release.release_id)
        return release

    def append_deployment(self, release_id: str, record: DeploymentRecord) -> None:
        release = self.get(release_id)
        if release is None:
            raise ReleaseNotFoundError(release_id)
        updated = release.with_deployment(record)
        dest_meta = self._paths.metadata_dir / f"{release_id}.json"
        _atomic_write(dest_meta, json.dumps(updated.to_dict(), indent=2, sort_keys=True), readonly=True)

    def apk_path(self, release_id: str) -> Path:
        return self._paths.apk_dir / f"{release_id}.apk"

    def _load_index(self) -> CatalogIndex:
        path = self._paths.catalog_index_path
        if not path.exists():
            return CatalogIndex(revision=0, release_ids=())
        data = json.loads(path.read_text(encoding="utf-8"))
        return CatalogIndex.from_dict(data)

    def _write_index(self, index: CatalogIndex) -> None:
        _atomic_write(
            self._paths.catalog_index_path,
            json.dumps(index.to_dict(), indent=2, sort_keys=True),
        )

    def _write_active(self, release_id: str) -> None:
        _atomic_write(
            self._paths.active_pointer_path,
            json.dumps({"release_id": release_id}, indent=2, sort_keys=True),
        )

    def _load_record(self, release_id: str) -> ReleaseRecord:
        path = self._paths.metadata_dir / f"{release_id}.json"
        data = json.loads(path.read_text(encoding="utf-8"))
        return ReleaseRecord.from_dict(data)


def _atomic_write(path: Path, content: str, *, readonly: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", dir=path.parent, prefix=f".{path.name}.", delete=False
    ) as tmp:
        tmp.write(content)
        tmp.flush()
        os.fsync(tmp.fileno())
        tmp_path = Path(tmp.name)
    if readonly:
        os.chmod(tmp_path, 0o400)
    else:
        os.chmod(tmp_path, 0o600)
    os.replace(tmp_path, path)
    if readonly:
        try:
            os.chmod(path, 0o400)
        except OSError:
            pass


def _atomic_copy(source: Path, destination: Path, *, readonly: bool = False) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        mode="wb", dir=destination.parent, prefix=f".{destination.name}.", delete=False
    ) as tmp:
        with open(source, "rb") as src:
            while True:
                chunk = src.read(65536)
                if not chunk:
                    break
                tmp.write(chunk)
        tmp.flush()
        os.fsync(tmp.fileno())
        tmp_path = Path(tmp.name)
    if readonly:
        os.chmod(tmp_path, 0o400)
    else:
        os.chmod(tmp_path, 0o600)
    os.replace(tmp_path, destination)
    if readonly:
        try:
            os.chmod(destination, 0o400)
        except OSError:
            pass
