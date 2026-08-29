import tempfile
import unittest
from pathlib import Path

from deploy.animal_heroes_deploy.operation_journal import (
    JournalError,
    JournalState,
    OperationJournal,
)


class OperationJournalTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmpdir = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmpdir.cleanup)
        self.journal = OperationJournal(Path(self._tmpdir.name))

    def test_create_and_read(self) -> None:
        entry = self.journal.create("op-1", {"version_name": "1.0.0-rc.1"})
        self.assertEqual(entry.state, JournalState.STAGED)
        read = self.journal.read("op-1")
        self.assertEqual(read.operation_id, "op-1")
        self.assertEqual(read.data["version_name"], "1.0.0-rc.1")

    def test_transition_merges_data(self) -> None:
        self.journal.create("op-1", {"version_name": "1.0.0-rc.1"})
        entry = self.journal.transition("op-1", JournalState.TAGGED, {"tag": "v1.0.0-rc.1"})
        self.assertEqual(entry.state, JournalState.TAGGED)
        self.assertEqual(entry.data["version_name"], "1.0.0-rc.1")
        self.assertEqual(entry.data["tag"], "v1.0.0-rc.1")

    def test_transition_preserves_existing_data(self) -> None:
        self.journal.create("op-1", {"version_name": "1.0.0-rc.1"})
        entry = self.journal.transition("op-1", JournalState.FAST_FORWARDED)
        self.assertEqual(entry.data["version_name"], "1.0.0-rc.1")

    def test_read_nonexistent_raises(self) -> None:
        with self.assertRaises(JournalError):
            self.journal.read("nonexistent")

    def test_exists(self) -> None:
        self.assertFalse(self.journal.exists("op-1"))
        self.journal.create("op-1", {})
        self.assertTrue(self.journal.exists("op-1"))

    def test_remove(self) -> None:
        self.journal.create("op-1", {})
        self.journal.remove("op-1")
        self.assertFalse(self.journal.exists("op-1"))

    def test_all_journal_states(self) -> None:
        states = [
            JournalState.STAGED,
            JournalState.REFS_PREFLIGHTED,
            JournalState.FAST_FORWARDED,
            JournalState.TAGGED,
            JournalState.CATALOG_PUBLISHED,
            JournalState.ACTIVE_SET,
            JournalState.COMPLETE,
        ]
        self.journal.create("op-1", {})
        for state in states[1:]:
            self.journal.transition("op-1", state)
        self.assertEqual(self.journal.read("op-1").state, JournalState.COMPLETE)
