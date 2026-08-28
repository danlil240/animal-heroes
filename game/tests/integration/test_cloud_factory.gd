extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene = load("res://levels/cloud_factory.tscn")
	if scene == null:
		_fail("cloud factory scene must exist")
		return
	var level = scene.instantiate()
	root.add_child(level)
	await process_frame
	await physics_frame
	var checkpoints: Array = level.get_tree().get_nodes_in_group("checkpoint")
	if checkpoints.size() < 4:
		_fail("cloud factory must have at least four checkpoints, got %d" % checkpoints.size())
		return
	var fans: Array = level.get_tree().get_nodes_in_group("fan_zone")
	if fans.size() < 3:
		_fail("cloud factory must have at least three fan zones, got %d" % fans.size())
		return
	var conveyors: Array = level.get_tree().get_nodes_in_group("conveyor")
	if conveyors.size() < 3:
		_fail("cloud factory must have at least three conveyors, got %d" % conveyors.size())
		return
	if level.get_node_or_null("BossEntrance") == null:
		_fail("cloud factory must have a BossEntrance node")
		return
	if int(level.get("enemy_budget")) > 12:
		_fail("cloud factory enemy_budget must be <= 12, got %d" % int(level.get("enemy_budget")))
		return
	if int(level.get("projectile_budget")) > 24:
		_fail("cloud factory projectile_budget must be <= 24, got %d" % int(level.get("projectile_budget")))
		return
	if int(level.get("particle_budget")) > 80:
		_fail("cloud factory particle_budget must be <= 80, got %d" % int(level.get("particle_budget")))
		return
	var spawns: Array = level.get_tree().get_nodes_in_group("player_spawn")
	if spawns.size() != 2:
		_fail("cloud factory must have exactly two player spawns, got %d" % spawns.size())
		return
	level.queue_free()
	await process_frame
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
