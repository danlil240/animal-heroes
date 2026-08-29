"""Update state orchestration for the deployment service."""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Callable


class UpdatePhase(str, Enum):
    IDLE = "idle"
    CHECKING = "checking"
    AVAILABLE = "available"
    REQUESTED = "requested"
    DEPLOYING = "deploying"
    COMPLETE = "complete"
    FAILED = "failed"
    SPLIT = "split"


_VALID_TRANSITIONS: dict[UpdatePhase, frozenset[UpdatePhase]] = {
    UpdatePhase.IDLE: frozenset({UpdatePhase.CHECKING}),
    UpdatePhase.CHECKING: frozenset({UpdatePhase.AVAILABLE, UpdatePhase.IDLE, UpdatePhase.FAILED}),
    UpdatePhase.AVAILABLE: frozenset({UpdatePhase.REQUESTED, UpdatePhase.IDLE}),
    UpdatePhase.REQUESTED: frozenset({UpdatePhase.DEPLOYING, UpdatePhase.FAILED}),
    UpdatePhase.DEPLOYING: frozenset({UpdatePhase.COMPLETE, UpdatePhase.FAILED, UpdatePhase.SPLIT}),
    UpdatePhase.COMPLETE: frozenset({UpdatePhase.IDLE}),
    UpdatePhase.FAILED: frozenset({UpdatePhase.IDLE}),
    UpdatePhase.SPLIT: frozenset({UpdatePhase.DEPLOYING, UpdatePhase.IDLE}),
}


class UpdateStateError(ValueError):
    """Raised when an invalid state transition is attempted."""


@dataclass(frozen=True)
class UpdateState:
    phase: UpdatePhase
    available_version_name: str | None = None
    available_version_code: int | None = None
    last_error: str | None = None
    deployment_state: str | None = None

    def transition_to(self, new_phase: UpdatePhase, **kwargs) -> "UpdateState":
        if new_phase not in _VALID_TRANSITIONS.get(self.phase, frozenset()):
            raise UpdateStateError(f"invalid transition: {self.phase.value} -> {new_phase.value}")
        return UpdateState(
            phase=new_phase,
            available_version_name=kwargs.get("available_version_name", self.available_version_name),
            available_version_code=kwargs.get("available_version_code", self.available_version_code),
            last_error=kwargs.get("last_error"),
            deployment_state=kwargs.get("deployment_state"),
        )

    def can_request_update(self) -> bool:
        return self.phase == UpdatePhase.AVAILABLE

    def is_busy(self) -> bool:
        return self.phase in (UpdatePhase.CHECKING, UpdatePhase.REQUESTED, UpdatePhase.DEPLOYING)


class UpdateStateMachine:
    def __init__(self, initial: UpdateState | None = None) -> None:
        self._state = initial or UpdateState(phase=UpdatePhase.IDLE)

    @property
    def state(self) -> UpdateState:
        return self._state

    def begin_check(self) -> UpdateState:
        self._state = self._state.transition_to(UpdatePhase.CHECKING)
        return self._state

    def report_available(self, version_name: str, version_code: int) -> UpdateState:
        self._state = self._state.transition_to(
            UpdatePhase.AVAILABLE,
            available_version_name=version_name,
            available_version_code=version_code,
        )
        return self._state

    def report_unavailable(self) -> UpdateState:
        self._state = self._state.transition_to(UpdatePhase.IDLE)
        return self._state

    def request_update(self) -> UpdateState:
        if not self._state.can_request_update():
            raise UpdateStateError("cannot request update when not in AVAILABLE phase")
        self._state = self._state.transition_to(UpdatePhase.REQUESTED)
        return self._state

    def begin_deploy(self) -> UpdateState:
        self._state = self._state.transition_to(UpdatePhase.DEPLOYING)
        return self._state

    def report_complete(self) -> UpdateState:
        self._state = self._state.transition_to(UpdatePhase.COMPLETE)
        return self._state

    def report_failed(self, error: str) -> UpdateState:
        self._state = self._state.transition_to(UpdatePhase.FAILED, last_error=error)
        return self._state

    def report_split(self, deployment_state: str) -> UpdateState:
        self._state = self._state.transition_to(UpdatePhase.SPLIT, deployment_state=deployment_state)
        return self._state

    def retry_split(self) -> UpdateState:
        self._state = self._state.transition_to(UpdatePhase.DEPLOYING)
        return self._state

    def reset(self) -> UpdateState:
        if self._state.phase in (UpdatePhase.CHECKING, UpdatePhase.AVAILABLE):
            self._state = self._state.transition_to(UpdatePhase.IDLE)
        elif self._state.phase in (UpdatePhase.COMPLETE, UpdatePhase.FAILED, UpdatePhase.SPLIT):
            self._state = self._state.transition_to(UpdatePhase.IDLE)
        return self._state
