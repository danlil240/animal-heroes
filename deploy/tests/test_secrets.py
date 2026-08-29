import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch, MagicMock

from deploy.animal_heroes_deploy.secrets import (
    GnomeKeyringSecretStore,
    Redactor,
    SecretError,
)
from deploy.animal_heroes_deploy.toolchain import Tool
from deploy.tests.fake_tools import fake_runner


class RedactorTests(unittest.TestCase):
    def test_redacts_known_secret_values(self) -> None:
        redactor = Redactor(values=("super-secret", "pair123"))
        self.assertEqual(redactor.redact("the password is super-secret"), "the password is [REDACTED]")
        self.assertEqual(redactor.redact("code pair123 here"), "code [REDACTED] here")

    def test_redacts_secret_field_names(self) -> None:
        redactor = Redactor(values=())
        text = "GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=hello"
        self.assertEqual(redactor.redact(text), "GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=[REDACTED]")

    def test_no_values_returns_original(self) -> None:
        redactor = Redactor(values=())
        self.assertEqual(redactor.redact("nothing secret here"), "nothing secret here")

    def test_with_values_combines(self) -> None:
        redactor = Redactor(values=("abc",))
        combined = redactor.with_values(("def",))
        self.assertEqual(combined.redact("abc and def"), "[REDACTED] and [REDACTED]")
        self.assertNotIn("abc", combined.redact("abc"))


class GnomeKeyringSecretStoreTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmpdir = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmpdir.cleanup)

    def test_store_and_lookup_round_trip(self) -> None:
        runner = fake_runner(self)
        store = GnomeKeyringSecretStore(runner)
        captured_stdin: list[bytes] = []
        captured_args: list[tuple] = []

        def fake_run(tool, args, *, cwd=None, stdin=None, env_additions=None, secret_values=(), timeout_s=120.0):
            captured_stdin.append(stdin or b"")
            captured_args.append(args)
            return MagicMock(returncode=0, stdout=b"the-secret\n")

        with patch.object(runner, "run", side_effect=fake_run):
            store.store("release-keystore-password", b"the-secret")
            result = store.lookup("release-keystore-password")

        self.assertEqual(result, b"the-secret")
        self.assertIn(b"the-secret", captured_stdin[0])
        self.assertIn("the-secret", str(captured_stdin[0]))
        self.assertEqual(captured_args[0][0], "store")
        self.assertEqual(captured_args[1][0], "lookup")
        # secret-tool store requires a --label argument; without it the call
        # fails with "must specify a label for the new item".
        self.assertTrue(
            any(arg.startswith("--label=") for arg in captured_args[0]),
            f"secret-tool store must include --label, got: {captured_args[0]}",
        )

    def test_lookup_returns_none_when_absent(self) -> None:
        runner = fake_runner(self)
        store = GnomeKeyringSecretStore(runner)
        with patch.object(runner, "run", return_value=MagicMock(returncode=1, stdout=b"")):
            self.assertIsNone(store.lookup("missing-key"))

    def test_store_passes_secret_only_via_stdin(self) -> None:
        runner = fake_runner(self)
        store = GnomeKeyringSecretStore(runner)
        captured_env: dict = {}
        captured_argv: list = []
        captured_stdin: list = []

        def fake_run(tool, args, *, cwd=None, stdin=None, env_additions=None, secret_values=(), timeout_s=120.0):
            captured_env.update(env_additions or {})
            captured_argv.extend(args)
            captured_stdin.append(stdin or b"")
            return MagicMock(returncode=0, stdout=b"")

        with patch.object(runner, "run", side_effect=fake_run):
            store.store("test-secret", b"my-password")

        self.assertIn(b"my-password", captured_stdin[0])
        for arg in captured_argv:
            self.assertNotIn("my-password", str(arg))
        for value in captured_env.values():
            self.assertNotIn("my-password", str(value))

    def test_clear_succeeds(self) -> None:
        runner = fake_runner(self)
        store = GnomeKeyringSecretStore(runner)
        with patch.object(runner, "run", return_value=MagicMock(returncode=0, stdout=b"")):
            store.clear("test-secret")
