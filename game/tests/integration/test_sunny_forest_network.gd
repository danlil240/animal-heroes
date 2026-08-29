extends SceneTree


func _init() -> void:
	call_deferred("_run")


## Catches out-of-range, wrong-sender, stale, or duplicate requests mutating a
## shared world, while proving the valid request uses the normal production path.
func _run() -> void:
	var arena = load("res://levels/test_arena.tscn").instantiate()
	arena.set_script(load("res://tests/support/world_level_fixture.gd"))
	root.add_child(arena)
	await process_frame
	if arena.process_world_action(0, 1, "push", "log", Vector2.ZERO):
		_fail("invalid peer id must be rejected")
		return
	if arena.process_world_action(2, 1, "push", "log", Vector2(500, 0)):
		_fail("out-of-range world action must be rejected")
		return
	if not arena.process_world_action(2, 2, "push", "log", Vector2(40, 0)):
		_fail("valid in-range world action must apply")
		return
	if arena.process_world_action(2, 2, "push", "log", Vector2(40, 0)):
		_fail("duplicate client sequence must be rejected")
		return
	if arena.process_world_action(2, 1, "push", "log", Vector2(40, 0)):
		_fail("stale client sequence must be rejected")
		return
	if arena.applied_event_count != 1 or arena.applied_payloads != [{"target_id": "log", "peer_id": 2}]:
		_fail("exactly one validated world event must reach the level")
		return
	if arena.last_world_event_sequence() != 1:
		_fail("first accepted world event must use sequence one")
		return
	arena.queue_free()
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
