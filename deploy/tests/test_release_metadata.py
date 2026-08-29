import json
import tempfile
import unittest
from pathlib import Path

from deploy.animal_heroes_deploy.release_metadata import (
    MetadataDriftError,
    MetadataError,
    ReleaseMetadata,
    check_checkout,
)


def valid_metadata_dict() -> dict[str, object]:
    return {
        "version_name": "1.0.0-dev.1",
        "version_code": 1,
        "application_protocol_version": 1,
        "save_schema_version": 1,
        "save_schema_compatible_min": 1,
        "save_schema_compatible_max": 1,
    }


def make_checkout(test_case: unittest.TestCase, version_name: str, version_code: int) -> Path:
    root = Path(tempfile.mkdtemp(dir=test_case._tmpdir.name))
    (root / "release").mkdir()
    (root / "game/core").mkdir(parents=True)
    (root / "game/export_presets.cfg").write_text(
        "[preset.0.options]\nversion/code=%d\nversion/name=\"%s\"\n"
        % (version_code, version_name),
        encoding="utf-8",
    )
    (root / "release/metadata.json").write_text(
        json.dumps(valid_metadata_dict()), encoding="utf-8"
    )
    (root / "game/core/build_info.gd").write_text("wrong generated build info\n", encoding="utf-8")
    return root


class ReleaseMetadataTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmpdir = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmpdir.cleanup)

    def test_valid_metadata_and_schema_range(self) -> None:
        metadata = ReleaseMetadata.from_dict(valid_metadata_dict())

        self.assertTrue(metadata.can_read_save_schema(1))
        self.assertFalse(metadata.can_read_save_schema(2))

    def test_rejects_unknown_keys_bad_semver_and_invalid_range(self) -> None:
        base = valid_metadata_dict()
        for patch in (
            {"extra": True},
            {"version_name": "release one"},
            {"version_code": 0},
            {"save_schema_compatible_min": 2},
        ):
            with self.subTest(patch=patch), self.assertRaises(MetadataError):
                ReleaseMetadata.from_dict(base | patch)

    def test_check_checkout_detects_generated_file_and_export_drift(self) -> None:
        root = make_checkout(self, version_name="wrong", version_code=99)

        with self.assertRaises(MetadataDriftError):
            check_checkout(root, ReleaseMetadata.load(root / "release/metadata.json"))
