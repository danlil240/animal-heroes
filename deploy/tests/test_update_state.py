import unittest

from deploy.animal_heroes_deploy.update_state import (
    UpdatePhase,
    UpdateState,
    UpdateStateError,
    UpdateStateMachine,
)


class UpdateStateMachineTests(unittest.TestCase):
    def test_initial_state_is_idle(self) -> None:
        sm = UpdateStateMachine()
        self.assertEqual(sm.state.phase, UpdatePhase.IDLE)
        self.assertFalse(sm.state.is_busy())
        self.assertFalse(sm.state.can_request_update())

    def test_check_available_request_deploy_complete(self) -> None:
        sm = UpdateStateMachine()
        sm.begin_check()
        self.assertEqual(sm.state.phase, UpdatePhase.CHECKING)
        sm.report_available("1.0.0-rc.1", 2)
        self.assertEqual(sm.state.phase, UpdatePhase.AVAILABLE)
        self.assertTrue(sm.state.can_request_update())
        sm.request_update()
        self.assertEqual(sm.state.phase, UpdatePhase.REQUESTED)
        sm.begin_deploy()
        self.assertEqual(sm.state.phase, UpdatePhase.DEPLOYING)
        self.assertTrue(sm.state.is_busy())
        sm.report_complete()
        self.assertEqual(sm.state.phase, UpdatePhase.COMPLETE)
        sm.reset()
        self.assertEqual(sm.state.phase, UpdatePhase.IDLE)

    def test_unavailable_returns_to_idle(self) -> None:
        sm = UpdateStateMachine()
        sm.begin_check()
        sm.report_unavailable()
        self.assertEqual(sm.state.phase, UpdatePhase.IDLE)

    def test_failed_path(self) -> None:
        sm = UpdateStateMachine()
        sm.begin_check()
        sm.report_available("1.0.0-rc.1", 2)
        sm.request_update()
        sm.report_failed("install error")
        self.assertEqual(sm.state.phase, UpdatePhase.FAILED)
        self.assertEqual(sm.state.last_error, "install error")
        sm.reset()
        self.assertEqual(sm.state.phase, UpdatePhase.IDLE)

    def test_split_retry(self) -> None:
        sm = UpdateStateMachine()
        sm.begin_check()
        sm.report_available("1.0.0-rc.1", 2)
        sm.request_update()
        sm.begin_deploy()
        sm.report_split("VERSION_SPLIT")
        self.assertEqual(sm.state.phase, UpdatePhase.SPLIT)
        sm.retry_split()
        self.assertEqual(sm.state.phase, UpdatePhase.DEPLOYING)
        sm.report_complete()
        self.assertEqual(sm.state.phase, UpdatePhase.COMPLETE)

    def test_invalid_transition_raises(self) -> None:
        sm = UpdateStateMachine()
        with self.assertRaises(UpdateStateError):
            sm.request_update()  # IDLE -> REQUESTED is invalid

    def test_cannot_request_when_not_available(self) -> None:
        sm = UpdateStateMachine()
        sm.begin_check()
        with self.assertRaises(UpdateStateError):
            sm.request_update()

    def test_busy_states(self) -> None:
        sm = UpdateStateMachine()
        sm.begin_check()
        self.assertTrue(sm.state.is_busy())
        sm.report_available("1.0.0-rc.1", 2)
        self.assertFalse(sm.state.is_busy())  # AVAILABLE is not busy
        sm.request_update()
        self.assertTrue(sm.state.is_busy())
