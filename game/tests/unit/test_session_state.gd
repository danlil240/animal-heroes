extends SceneTree


func _init() -> void:
	var state = load("res://network/session_state.gd")
	if state == null:
		_fail("session state contract must exist")
		return
	if not state.is_valid_transition(state.IDLE, state.DISCOVERING):
		_fail("idle must allow discovery")
		return
	if not state.is_valid_transition(state.CONNECTING, state.LOBBY):
		_fail("connecting must allow lobby")
		return
	if state.is_valid_transition(state.PLAYING, state.CONNECTING):
		_fail("playing must not return directly to connecting")
		return
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
