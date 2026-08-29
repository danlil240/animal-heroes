"""Candidate release staging and publication pipeline."""

from __future__ import annotations

import hashlib
import json
import secrets
import shutil
import tempfile
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Mapping

from deploy.animal_heroes_deploy.apk import ApkInspector
from deploy.animal_heroes_deploy.audit import AuditEvent, AuditLog
from deploy.animal_heroes_deploy.catalog import Catalog
from deploy.animal_heroes_deploy.config import DeployConfig
from deploy.animal_heroes_deploy.domain import ReleaseChannel, ReleaseRecord
from deploy.animal_heroes_deploy.git_release import (
    CheckoutChanged,
    GitReleaseOps,
    GitReleaseError,
)
from deploy.animal_heroes_deploy.operation_journal import JournalState, OperationJournal
from deploy.animal_heroes_deploy.release_metadata import ReleaseMetadata, sync_checkout
from deploy.animal_heroes_deploy.secrets import GnomeKeyringSecretStore
from deploy.animal_heroes_deploy.commands import CommandRunner
from deploy.animal_heroes_deploy.toolchain import Tool


class ReleasePipelineError(RuntimeError):
    """Raised when the release pipeline fails."""


class StageRejected(ReleasePipelineError):
    """Raised when staging prerequisites are not met."""


class ConfirmRejected(ReleasePipelineError):
    """Raised when publication confirmation fails."""


@dataclass(frozen=True)
class CandidateRequest:
    version_name: str
    release_notes: str
    activate: bool = False
    source_commit: str | None = None
    rollback_of: str | None = None


@dataclass(frozen=True)
class StagedRelease:
    operation_id: str
    version_name: str
    version_code: int
    release_commit: str
    source_commit: str
    staged_apk_path: Path
    apk_sha256: str
    apk_size: int
    signer_sha256: str
    tag: str
    rollback_of: str | None
    worktree_path: Path


class ReleasePipeline:
    def __init__(
        self,
        *,
        config: DeployConfig,
        catalog: Catalog,
        runner: CommandRunner,
        git_ops: GitReleaseOps,
        apk_inspector: ApkInspector,
        secret_store: GnomeKeyringSecretStore,
        audit_log: AuditLog,
        journal: OperationJournal,
        repo_root: Path,
        expected_branch: str = "codex/release-candidate-stabilization",
        now: datetime | None = None,
    ) -> None:
        self._config = config
        self._catalog = catalog
        self._runner = runner
        self._git_ops = git_ops
        self._apk_inspector = apk_inspector
        self._secret_store = secret_store
        self._audit_log = audit_log
        self._journal = journal
        self._repo_root = repo_root
        self._expected_branch = expected_branch
        self._now = now or datetime.now(timezone.utc)

    def stage_candidate(self, request: CandidateRequest) -> StagedRelease:
        operation_id = secrets.token_hex(8)
        try:
            snapshot = self._git_ops.verify_clean(self._expected_branch, self._git_ops.snapshot().remote_url)
        except GitReleaseError as error:
            raise StageRejected(str(error)) from error
        source_commit = request.source_commit or snapshot.head_sha
        existing = self._catalog.list_releases()
        catalog_max = max((r.version_code for r in existing), default=0)
        source_metadata = ReleaseMetadata.load(self._repo_root / "release/metadata.json")
        version_code = max(source_metadata.version_code, catalog_max) + 1
        if self._git_ops.ref_exists(f"refs/tags/v{request.version_name}"):
            raise StageRejected(f"tag v{request.version_name} already exists")
        branch_name = f"codex/release-{request.version_name}"
        if self._git_ops.ref_exists(f"refs/heads/{branch_name}"):
            raise StageRejected(f"branch {branch_name} already exists")
        worktree = self._git_ops.create_worktree(source_commit, branch_name)
        try:
            new_metadata = ReleaseMetadata(
                version_name=request.version_name,
                version_code=version_code,
                application_protocol_version=source_metadata.application_protocol_version,
                save_schema_version=source_metadata.save_schema_version,
                save_schema_compatible_min=source_metadata.save_schema_compatible_min,
                save_schema_compatible_max=source_metadata.save_schema_compatible_max,
            )
            sync_checkout(worktree, new_metadata)
            self._update_changelog(worktree, request)
            release_commit = self._git_ops.commit_all(worktree, f"release: {request.version_name}")
            test_result = self._runner.run_repo_script(Path("scripts/test_all.sh"))
            if test_result.returncode != 0:
                raise StageRejected(f"test suite failed: {test_result.redacted_summary}")
            staged_apk = self._export_apk(worktree, request.version_name)
            facts = self._apk_inspector.verify(
                staged_apk,
                expected_version_name=request.version_name,
                expected_version_code=version_code,
                expected_signer_sha256=self._config.pinned_signer_sha256,
                expected_apk_sha256=_compute_sha256(staged_apk),
            )
            staged = StagedRelease(
                operation_id=operation_id,
                version_name=request.version_name,
                version_code=version_code,
                release_commit=release_commit,
                source_commit=source_commit,
                staged_apk_path=staged_apk,
                apk_sha256=facts.apk_sha256,
                apk_size=facts.apk_size,
                signer_sha256=facts.signer_sha256,
                tag=f"v{request.version_name}",
                rollback_of=request.rollback_of,
                worktree_path=worktree,
            )
            self._journal.create(operation_id, {
                "version_name": request.version_name,
                "version_code": version_code,
                "release_commit": release_commit,
                "source_commit": source_commit,
                "staged_apk_path": str(staged_apk),
                "apk_sha256": facts.apk_sha256,
                "apk_size": facts.apk_size,
                "signer_sha256": facts.signer_sha256,
                "tag": staged.tag,
                "rollback_of": request.rollback_of,
                "activate": request.activate,
                "worktree_path": str(worktree),
                "original_head": snapshot.head_sha,
            })
            self._audit_log.append(AuditEvent(
                operation_id=operation_id,
                timestamp=self._now.isoformat(),
                action="stage_candidate",
                initiator="dashboard",
                details={"version_name": request.version_name, "version_code": version_code},
            ))
            return staged
        except Exception:
            self._git_ops.remove_worktree(worktree)
            raise

    def confirm_publish(self, operation_id: str) -> ReleaseRecord:
        entry = self._journal.read(operation_id)
        if entry.state != JournalState.STAGED:
            raise ConfirmRejected(f"operation {operation_id} is not in STAGED state")
        data = entry.data
        snapshot = self._git_ops.snapshot()
        if data["original_head"] != snapshot.head_sha or not snapshot.is_clean:
            raise CheckoutChanged("original checkout changed since staging")
        self._journal.transition(operation_id, JournalState.REFS_PREFLIGHTED)
        if self._git_ops.ref_exists(f"refs/tags/{data['tag']}"):
            raise ConfirmRejected(f"tag {data['tag']} already exists")
        self._git_ops.fast_forward(self._expected_branch, data["release_commit"])
        self._journal.transition(operation_id, JournalState.FAST_FORWARDED, {"ff_branch": self._expected_branch})
        self._git_ops.create_tag(self._repo_root, data["tag"], data["release_commit"])
        self._journal.transition(operation_id, JournalState.TAGGED)
        metadata = ReleaseMetadata(
            version_name=data["version_name"],
            version_code=int(data["version_code"]),
            application_protocol_version=1,
            save_schema_version=1,
            save_schema_compatible_min=1,
            save_schema_compatible_max=1,
        )
        record = ReleaseRecord(
            release_id=f"{int(data['version_code']):010d}-{data['version_name']}",
            version_name=data["version_name"],
            version_code=int(data["version_code"]),
            channel=ReleaseChannel.CANDIDATE,
            source_commit=data["source_commit"],
            release_commit=data["release_commit"],
            tag=data["tag"],
            built_at=self._now.isoformat(),
            package_id=self._config.package_id,
            apk_size=int(data["apk_size"]),
            apk_sha256=data["apk_sha256"],
            signer_sha256=data["signer_sha256"],
            permissions=frozenset({"INTERNET", "ACCESS_NETWORK_STATE", "ACCESS_WIFI_STATE", "CHANGE_WIFI_MULTICAST_STATE"}),
            managed_metadata=metadata,
            rollback_of=data.get("rollback_of"),
            deployments=(),
        )
        self._catalog.publish(Path(data["staged_apk_path"]), record)
        self._journal.transition(operation_id, JournalState.CATALOG_PUBLISHED)
        if data.get("activate"):
            revision = self._catalog.revision()
            self._catalog.set_active(record.release_id, expected_revision=revision)
            self._journal.transition(operation_id, JournalState.ACTIVE_SET)
        self._journal.transition(operation_id, JournalState.COMPLETE)
        self._cleanup_worktree(data)
        self._journal.remove(operation_id)
        self._audit_log.append(AuditEvent(
            operation_id=operation_id,
            timestamp=self._now.isoformat(),
            action="confirm_publish",
            initiator="dashboard",
            details={"version_name": record.version_name, "version_code": record.version_code},
        ))
        return record

    def _export_apk(self, worktree: Path, version_name: str) -> Path:
        staging_dir = self._catalog._paths.runtime / "staging" / version_name
        staging_dir.mkdir(parents=True, exist_ok=True)
        apk_path = staging_dir / "release.apk"
        password = self._secret_store.lookup("release-keystore-password")
        if password is None:
            raise StageRejected("keystore password not found in keyring")
        signing_env = {
            "GODOT_ANDROID_KEYSTORE_RELEASE_PATH": str(self._config.keystore_path),
            "GODOT_ANDROID_KEYSTORE_RELEASE_USER": self._config.keystore_alias,
            "GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD": password.decode("utf-8"),
        }
        result = self._runner.run(
            Tool.GODOT,
            ("--headless", "--path", str(worktree / "game"), "--export-release", "Android", str(apk_path)),
            cwd=worktree,
            env_additions=signing_env,
            secret_values=(signing_env["GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD"],),
            timeout_s=1800.0,
        )
        if result.returncode != 0:
            raise StageRejected(f"godot export failed: {result.redacted_summary}")
        return apk_path

    def _update_changelog(self, worktree: Path, request: CandidateRequest) -> None:
        changelog_path = worktree / "CHANGELOG.md"
        if changelog_path.exists():
            content = changelog_path.read_text(encoding="utf-8")
        else:
            content = ""
        entry = f"## {request.version_name}\n\n{request.release_notes}\n"
        changelog_path.write_text(entry + content, encoding="utf-8")

    def _cleanup_worktree(self, data: Mapping[str, Any]) -> None:
        worktree_path = Path(data.get("worktree_path", ""))
        if worktree_path.exists():
            self._git_ops.remove_worktree(worktree_path)


def _compute_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        while True:
            chunk = f.read(65536)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()
