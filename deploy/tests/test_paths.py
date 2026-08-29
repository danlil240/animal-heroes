import os
import tempfile
import unittest
from pathlib import Path

from deploy.animal_heroes_deploy.paths import (
    APP_DIR,
    PathBoundaryError,
    StatePaths,
    require_child,
)


class StatePathsTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmpdir = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmpdir.cleanup)
        self.home = Path(self._tmpdir.name) / "home"
        self.home.mkdir()

    def test_resolve_uses_xdg_directories(self) -> None:
        config_home = self._tmpdir.name / Path("xdg/config")  # type: ignore[operator]
        data_home = Path(self._tmpdir.name) / "xdg/data"
        runtime = Path(self._tmpdir.name) / "xdg/runtime"
        for path in (config_home, data_home, runtime):
            path.mkdir(parents=True)
        paths = StatePaths.resolve(
            {
                "HOME": str(self.home),
                "XDG_CONFIG_HOME": str(config_home),
                "XDG_DATA_HOME": str(data_home),
                "XDG_RUNTIME_DIR": str(runtime),
            },
            uid=1000,
        )
        self.assertEqual(paths.config, config_home / APP_DIR)
        self.assertEqual(paths.data, data_home / APP_DIR)
        self.assertEqual(paths.runtime, runtime / APP_DIR)

    def test_resolve_falls_back_to_defaults(self) -> None:
        paths = StatePaths.resolve({"HOME": str(self.home)}, uid=1000)
        self.assertEqual(paths.config, self.home / ".config" / APP_DIR)
        self.assertEqual(paths.data, self.home / ".local/share" / APP_DIR)
        self.assertTrue(paths.runtime.name == APP_DIR)

    def test_for_test_uses_single_root(self) -> None:
        root = Path(self._tmpdir.name)
        paths = StatePaths.for_test(root)
        self.assertEqual(paths.config, root / "config")
        self.assertEqual(paths.data, root / "data")
        self.assertEqual(paths.runtime, root / "runtime")


class RequireChildTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmpdir = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmpdir.cleanup)
        self.base = Path(self._tmpdir.name) / "base"
        self.base.mkdir()

    def test_accepts_direct_child(self) -> None:
        child = self.base / "child.txt"
        child.write_text("ok", encoding="utf-8")
        self.assertEqual(require_child(self.base, child), child.resolve())

    def test_accepts_nested_child(self) -> None:
        nested = self.base / "dir" / "file.txt"
        nested.parent.mkdir(parents=True)
        nested.write_text("ok", encoding="utf-8")
        self.assertEqual(require_child(self.base, nested), nested.resolve())

    def test_rejects_parent(self) -> None:
        with self.assertRaises(PathBoundaryError):
            require_child(self.base, self.base.parent)

    def test_rejects_symlink_escape(self) -> None:
        outside = Path(self._tmpdir.name) / "outside"
        outside.mkdir()
        link = self.base / "link"
        link.symlink_to(outside, target_is_directory=True)
        with self.assertRaises(PathBoundaryError):
            require_child(self.base, link / "file")

    def test_rejects_base_itself(self) -> None:
        with self.assertRaises(PathBoundaryError):
            require_child(self.base, self.base)
