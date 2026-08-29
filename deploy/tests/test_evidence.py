import unittest
from dataclasses import replace

from deploy.animal_heroes_deploy.evidence import (
    EvidenceBundle,
    EvidenceEntry,
    EvidenceRejected,
    PromotionGate,
    REQUIRED_STABLE_GATES,
    replace_gate,
    valid_evidence_bundle,
)


class EvidenceEntryTests(unittest.TestCase):
    def test_valid_entry(self) -> None:
        entry = EvidenceEntry(evidence_path="/evidence/test.txt", date="2026-08-29", operator="op1")
        entry.validate()

    def test_rejects_empty_path(self) -> None:
        entry = EvidenceEntry(evidence_path="", date="2026-08-29", operator="op1")
        with self.assertRaises(EvidenceRejected):
            entry.validate()

    def test_rejects_empty_date(self) -> None:
        entry = EvidenceEntry(evidence_path="/evidence/test.txt", date="", operator="op1")
        with self.assertRaises(EvidenceRejected):
            entry.validate()

    def test_rejects_empty_operator(self) -> None:
        entry = EvidenceEntry(evidence_path="/evidence/test.txt", date="2026-08-29", operator="")
        with self.assertRaises(EvidenceRejected):
            entry.validate()


class EvidenceBundleTests(unittest.TestCase):
    def test_valid_bundle_passes(self) -> None:
        bundle = valid_evidence_bundle()
        PromotionGate().validate(bundle)

    def test_every_stable_gate_requires_evidence(self) -> None:
        bundle = valid_evidence_bundle()
        for gate in REQUIRED_STABLE_GATES:
            invalid = replace_gate(bundle, gate, evidence_path="")
            with self.subTest(gate=gate), self.assertRaises(EvidenceRejected):
                PromotionGate().validate(invalid)

    def test_missing_gate_rejected(self) -> None:
        entries = dict(valid_evidence_bundle().entries)
        del entries["dual_sm_t220"]
        bundle = EvidenceBundle(entries=entries)
        with self.assertRaises(EvidenceRejected):
            PromotionGate().validate(bundle)

    def test_all_required_gates_present(self) -> None:
        bundle = valid_evidence_bundle()
        for gate in REQUIRED_STABLE_GATES:
            self.assertIn(gate, bundle.entries)
