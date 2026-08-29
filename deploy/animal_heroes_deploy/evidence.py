"""Stable release evidence gates and validation."""

from __future__ import annotations

from dataclasses import dataclass, field, replace
from enum import Enum
from typing import Mapping


class EvidenceRejected(ValueError):
    """Raised when stable evidence is incomplete or invalid."""


REQUIRED_STABLE_GATES = (
    "dual_sm_t220",
    "hebrew_review",
    "two_child_sessions",
    "audio_rights_or_replacement",
    "keystore_backup",
    "candidate_lineage_install_smoke",
)


@dataclass(frozen=True)
class EvidenceEntry:
    evidence_path: str
    date: str
    operator: str

    def validate(self) -> None:
        if not self.evidence_path:
            raise EvidenceRejected("evidence path must not be empty")
        if not self.date:
            raise EvidenceRejected("evidence date must not be empty")
        if not self.operator:
            raise EvidenceRejected("evidence operator must not be empty")


@dataclass(frozen=True)
class EvidenceBundle:
    entries: Mapping[str, EvidenceEntry] = field(default_factory=dict)

    @classmethod
    def from_dict(cls, value: Mapping[str, Mapping[str, str]]) -> "EvidenceBundle":
        entries = {gate: EvidenceEntry(**entry) for gate, entry in value.items()}
        return cls(entries=entries)

    def validate(self) -> None:
        for gate in REQUIRED_STABLE_GATES:
            if gate not in self.entries:
                raise EvidenceRejected(f"missing required gate: {gate}")
            self.entries[gate].validate()


class PromotionGate:
    def validate(self, bundle: EvidenceBundle) -> None:
        bundle.validate()


def replace_gate(bundle: EvidenceBundle, gate: str, **kwargs) -> EvidenceBundle:
    new_entry = replace(bundle.entries[gate], **kwargs)
    new_entries = {**bundle.entries, gate: new_entry}
    return EvidenceBundle(entries=new_entries)


def valid_evidence_bundle() -> EvidenceBundle:
    entries = {
        gate: EvidenceEntry(evidence_path=f"/evidence/{gate}.txt", date="2026-08-29", operator="operator1")
        for gate in REQUIRED_STABLE_GATES
    }
    return EvidenceBundle(entries=entries)
