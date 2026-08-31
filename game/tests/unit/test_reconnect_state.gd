extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
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
	if not await _test_sunny_forest_rich_snapshot_is_atomic():
		return
	quit(0)


## Sunny Forest's rich reconnect snapshot must include secrets and brambles,
## and a rejected snapshot must not partially mutate live state.
func _test_sunny_forest_rich_snapshot_is_atomic() -> bool:
	var scene = load("res://levels/sunny_forest.tscn")
	if scene == null:
		_fail("sunny forest scene must exist for rich reconnect test")
		return false
	var level = scene.instantiate()
	root.add_child(level)
	await process_frame
	await physics_frame
	level.discover_secret("momentum-carrot", 1)
	var secrets_before: int = level.discovered_secret_count()
	var snapshot: Dictionary = level.world_state_snapshot()
	if not snapshot.has("secrets") or not snapshot.has("brambles"):
		_fail("rich snapshot must include secrets and brambles")
		level.queue_free()
		return false
	if (snapshot["secrets"] as Array).size() != 3:
		_fail("rich snapshot must include all three secret triggers")
		level.queue_free()
		return false
	# A snapshot missing a required key must be rejected without mutating state.
	var incomplete := snapshot.duplicate(true)
	incomplete.erase("secrets")
	var score_before: int = level.team_score.total
	if level.restore_world_state(incomplete):
		_fail("restore must reject a snapshot missing the secrets key")
		level.queue_free()
		return false
	if level.discovered_secret_count() != secrets_before or level.team_score.total != score_before:
		_fail("a rejected snapshot must not partially mutate live state")
		level.queue_free()
		return false
	# A valid snapshot must restore secrets exactly.
	if not level.restore_world_state(snapshot):
		_fail("a valid rich snapshot must restore")
		level.queue_free()
		return false
	if level.discovered_secret_count() != secrets_before:
		_fail("rich snapshot restore must preserve discovered secret count")
		level.queue_free()
		return false
	level.queue_free()
	await process_frame
	return true


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
