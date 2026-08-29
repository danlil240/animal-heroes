"""Safe rollback planning through the candidate pipeline."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Sequence

from deploy.animal_heroes_deploy.catalog import Catalog
from deploy.animal_heroes_deploy.domain import DeploymentRecord, DeploymentState, ReleaseRecord
from deploy.animal_heroes_deploy.release_pipeline import CandidateRequest


class IncompatibleRollback(ValueError):
    """Raised when a rollback source cannot safely replace the deployed version."""


class RollbackPlanner:
    def __init__(self, catalog: Catalog) -> None:
        self._catalog = catalog

    def prepare(self, source_release_id: str, new_version_name: str) -> CandidateRequest:
        source = self._catalog.get(source_release_id)
        if source is None:
            raise IncompatibleRollback("source release not found")
        if source.managed_metadata is None:
            raise IncompatibleRollback("source release predates managed metadata")
        if not source.source_commit:
            raise IncompatibleRollback("source release has no source commit")
        current_schema = self._deployed_pair_schema()
        if current_schema is None:
            raise IncompatibleRollback("cannot determine deployed save schema")
        if not source.managed_metadata.save_schema_compatible_min <= current_schema <= source.managed_metadata.save_schema_compatible_max:
            raise IncompatibleRollback("selected source cannot read deployed saves")
        existing_names = {r.version_name for r in self._catalog.list_releases()}
        if new_version_name in existing_names:
            raise IncompatibleRollback("version name already exists in catalog")
        return CandidateRequest(
            version_name=new_version_name,
            release_notes=f"Safe rollback of {source.version_name}",
            activate=False,
            source_commit=source.source_commit,
            rollback_of=source.release_id,
        )

    def _deployed_pair_schema(self) -> int | None:
        active = self._catalog.active()
        if active is None:
            return None
        return active.managed_metadata.save_schema_version
