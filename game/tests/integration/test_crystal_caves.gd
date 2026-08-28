extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene = load("res://levels/crystal_caves.tscn")
	if scene == null:
		_fail("crystal caves scene must exist")
		return
	var level = scene.instantiate()
	root.add_child(level)
	await process_frame
	await physics_frame
	var checkpoints: Array = level.get_tree().get_nodes_in_group("checkpoint")
	if checkpoints.size() < 4:
		_fail("crystal caves must have at least four checkpoints, got %d" % checkpoints.size())
		return
	var moving_platforms: Array = level.get_tree().get_nodes_in_group("moving_platform")
	if moving_platforms.size() < 2:
		_fail("crystal caves must have at least two moving platforms, got %d" % moving_platforms.size())
		return
	var switch_door_pairs: Array = level.get_tree().get_nodes_in_group("switch_door_pair")
	if switch_door_pairs.size() < 2:
		_fail("crystal caves must have at least two switch-door pairs, got %d" % switch_door_pairs.size())
		return
	var heavy_pushables: Array = level.get_tree().get_nodes_in_group("heavy_pushable")
	if heavy_pushables.size() < 1:
		_fail("crystal caves must have at least one heavy pushable")
		return
	var reunion_routes: Array = level.get_tree().get_nodes_in_group("reunion_route")
	if reunion_routes.size() < 2:
		_fail("crystal caves must have at least two reunion routes, got %d" % reunion_routes.size())
		return
	var spawns: Array = level.get_tree().get_nodes_in_group("player_spawn")
	if spawns.size() != 2:
		_fail("crystal caves must have exactly two player spawns, got %d" % spawns.size())
		return
	level.queue_free()
	await process_frame
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
