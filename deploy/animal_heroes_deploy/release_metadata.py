"""Canonical release metadata and generated checkout files."""

from __future__ import annotations

from dataclasses import dataclass
import json
import os
from pathlib import Path
import re
import tempfile
from typing import Mapping


REQUIRED_KEYS = frozenset(
    {
        "version_name",
        "version_code",
        "application_protocol_version",
        "save_schema_version",
        "save_schema_compatible_min",
        "save_schema_compatible_max",
    }
)
SEMVER = re.compile(
    r"(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)"
    r"(?:-(?:0|[1-9]\d*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*)(?:\.(?:0|[1-9]\d*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*))*)?"
    r"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?"
)


class MetadataError(ValueError):
    """Raised when canonical release metadata is malformed."""


class MetadataDriftError(MetadataError):
    """Raised when generated checkout files diverge from canonical metadata."""


@dataclass(frozen=True)
class ReleaseMetadata:
    version_name: str
    version_code: int
    application_protocol_version: int
    save_schema_version: int
    save_schema_compatible_min: int
    save_schema_compatible_max: int

    @classmethod
    def from_dict(cls, value: Mapping[str, object]) -> "ReleaseMetadata":
        if set(value) != REQUIRED_KEYS:
            raise MetadataError("release metadata keys are invalid")
        metadata = cls(**{key: value[key] for key in REQUIRED_KEYS})
        metadata.validate()
        return metadata

    @classmethod
    def load(cls, path: Path) -> "ReleaseMetadata":
        try:
            value = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            raise MetadataError("release metadata cannot be loaded") from error
        if not isinstance(value, dict):
            raise MetadataError("release metadata must be an object")
        return cls.from_dict(value)

    def validate(self) -> None:
        if type(self.version_name) is not str or SEMVER.fullmatch(self.version_name) is None:
            raise MetadataError("version_name must be Semantic Versioning")
        integer_values = (
            self.version_code,
            self.application_protocol_version,
            self.save_schema_version,
            self.save_schema_compatible_min,
            self.save_schema_compatible_max,
        )
        if any(type(value) is not int or value <= 0 for value in integer_values):
            raise MetadataError("release numeric fields must be positive integers")
        if not self.save_schema_compatible_min <= self.save_schema_version <= self.save_schema_compatible_max:
            raise MetadataError("save schema compatibility range is invalid")

    def can_read_save_schema(self, schema: int) -> bool:
        return (
            type(schema) is int
            and self.save_schema_compatible_min <= schema <= self.save_schema_compatible_max
        )


def render_build_info(metadata: ReleaseMetadata) -> str:
    return f'''class_name BuildInfo
extends RefCounted

const VERSION_NAME := "{metadata.version_name}"
const VERSION_CODE := {metadata.version_code}
const APPLICATION_PROTOCOL_VERSION := {metadata.application_protocol_version}
const SAVE_SCHEMA_VERSION := {metadata.save_schema_version}
const SAVE_SCHEMA_COMPATIBLE_MIN := {metadata.save_schema_compatible_min}
const SAVE_SCHEMA_COMPATIBLE_MAX := {metadata.save_schema_compatible_max}

static func current() -> Dictionary:
\treturn {{
\t\t"version_name": VERSION_NAME,
\t\t"version_code": VERSION_CODE,
\t\t"application_protocol_version": APPLICATION_PROTOCOL_VERSION,
\t\t"save_schema_version": SAVE_SCHEMA_VERSION,
\t}}
'''


def render_export_presets(existing: str, metadata: ReleaseMetadata) -> str:
    rendered, code_count = re.subn(
        r"(?m)^version/code=.*$", f"version/code={metadata.version_code}", existing
    )
    rendered, name_count = re.subn(
        r'(?m)^version/name=.*$', f'version/name="{metadata.version_name}"', rendered
    )
    if code_count != 1 or name_count != 1:
        raise MetadataError("Android export preset must contain exactly one version/code and version/name")
    return rendered


def _atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", dir=path.parent, prefix=f".{path.name}.", delete=False
    ) as temporary:
        temporary.write(content)
        temporary.flush()
        os.fsync(temporary.fileno())
        temporary_path = Path(temporary.name)
    os.replace(temporary_path, path)


def _render_checkout(root: Path, metadata: ReleaseMetadata) -> dict[Path, str]:
    preset_path = root / "game/export_presets.cfg"
    try:
        export_presets = preset_path.read_text(encoding="utf-8")
    except OSError as error:
        raise MetadataError("Android export preset cannot be loaded") from error
    return {
        root / "game/core/build_info.gd": render_build_info(metadata),
        preset_path: render_export_presets(export_presets, metadata),
    }


def sync_checkout(root: Path, metadata: ReleaseMetadata) -> None:
    metadata.validate()
    for path, content in _render_checkout(root, metadata).items():
        _atomic_write(path, content)


def check_checkout(root: Path, metadata: ReleaseMetadata) -> None:
    metadata.validate()
    for path, expected in _render_checkout(root, metadata).items():
        try:
            actual = path.read_text(encoding="utf-8")
        except OSError as error:
            raise MetadataDriftError(f"generated file is missing: {path}") from error
        if actual != expected:
            raise MetadataDriftError(f"generated file differs from release metadata: {path}")
