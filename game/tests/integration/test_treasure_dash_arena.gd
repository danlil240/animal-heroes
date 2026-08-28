extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var arena_scene = load("res://levels/treasure_dash_arena.tscn")
	if arena_scene == null:
		_fail("treasure_dash_arena.tscn must exist")
		return
	var arena = arena_scene.instantiate()
	root.add_child(arena)
	await process_frame
	await physics_frame
	var spawns: Array = arena.get_tree().get_nodes_in_group("player_spawn")
	if spawns.size() != 2:
		_fail("arena must have exactly 2 player spawns, got %d" % spawns.size())
		return
	var spawn_points: Array = arena.get_tree().get_nodes_in_group("td_spawn_point")
	if spawn_points.size() < 8:
		_fail("arena must have at least 8 collectible spawn points, got %d" % spawn_points.size())
		return
	if arena.get_node_or_null("FallRespawn") == null:
		_fail("arena must have a FallRespawn node")
		return
	if arena.get_node_or_null("Rabbit") == null or arena.get_node_or_null("Fox") == null:
		_fail("arena must have Rabbit and Fox players")
		return
	if arena.dash_mode == null:
		_fail("arena must initialize with a dash_mode")
		return
	if arena.dash_mode.is_finished():
		_fail("arena dash_mode must start unfinished")
		return
	if arena.dash_mode.time_remaining() <= 0.0:
		_fail("arena dash_mode must have positive time remaining")
		return
	if int(arena.rabbit.get_meta("peer_id", 0)) != 1:
		_fail("rabbit must have peer_id meta 1")
		return
	if int(arena.fox.get_meta("peer_id", 0)) != 2:
		_fail("fox must have peer_id meta 2")
		return
	arena.queue_free()
	await process_frame
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
