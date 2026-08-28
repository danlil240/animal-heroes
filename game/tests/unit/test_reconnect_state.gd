extends SceneTree


func _init() -> void:
	var controller_script = load("res://network/reconnect_controller.gd")
	if controller_script == null:
		_fail("reconnect controller must exist")
		return
	var controller = controller_script.new()
	controller.connection_lost("session42")
	if controller.state != controller.RETRYING:
		_fail("connection_lost must enter retrying state")
		return
	controller.tick(14.9)
	if controller.state != controller.RETRYING:
		_fail("retry must continue inside the 15-second window")
		return
	controller.tick(0.2)
	if controller.state != controller.FAILED:
		_fail("retry must fail after the 15-second window elapses")
		return
	controller.reset()
	if controller.state != controller.IDLE:
		_fail("reset must return the controller to idle")
		return
	controller.connection_lost("session42")
	controller.restore("session42")
	if controller.state != controller.RESTORED:
		_fail("restore with a matching session id must transition to restored")
		return
	controller.reset()
	controller.connection_lost("session42")
	controller.restore("other-session")
	if controller.state != controller.RETRYING:
		_fail("restore with a mismatched session id must keep retrying")
		return
	var checkpoint_state = load("res://core/checkpoint_state.gd")
	if checkpoint_state == null:
		_fail("checkpoint state contract must exist")
		return
	var checkpoint = checkpoint_state.from_dict({
		"level_id": "sunny_forest",
		"checkpoint_id": "cp-2",
		"unlocked_levels": ["sunny_forest", "crystal_caves"],
		"hero_state": {"peer_id": 1, "hearts": 3},
	})
	if checkpoint.level_id != "sunny_forest" or checkpoint.checkpoint_id != "cp-2":
		_fail("checkpoint state must parse level and checkpoint ids")
		return
	if checkpoint.unlocked_levels != ["sunny_forest", "crystal_caves"]:
		_fail("checkpoint state must preserve unlocked levels")
		return
	var round_trip: Dictionary = checkpoint.to_dict()
	if round_trip.get("checkpoint_id") != "cp-2" or round_trip.get("hero_state", {}).get("hearts") != 3:
		_fail("checkpoint state must round-trip through a dictionary")
		return
	if checkpoint_state.from_dict({"level_id": "sunny_forest"}) != null:
		_fail("checkpoint state must reject incomplete dictionaries")
		return
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
