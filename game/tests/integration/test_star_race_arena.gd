extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var arena_scene = load("res://levels/star_race_arena.tscn")
	if arena_scene == null:
		_fail("star_race_arena.tscn must exist")
		return
	var arena = arena_scene.instantiate()
	root.add_child(arena)
	await process_frame
	await physics_frame
	var spawns: Array = arena.get_tree().get_nodes_in_group("player_spawn")
	if spawns.size() != 2:
		_fail("arena must have exactly 2 player spawns, got %d" % spawns.size())
		return
	var checkpoints: Array = arena.get_tree().get_nodes_in_group("race_checkpoint")
	if checkpoints.size() != 4:
		_fail("arena must have exactly 4 race checkpoints, got %d" % checkpoints.size())
		return
	var ids: Array = []
	for cp in checkpoints:
		ids.append(cp.checkpoint_id)
	ids.sort()
	if ids != ["rcp-1", "rcp-2", "rcp-3", "rcp-4"]:
		_fail("race checkpoint ids must be rcp-1 through rcp-4, got %s" % str(ids))
		return
	if arena.get_node_or_null("FinishLine") == null:
		_fail("arena must have a FinishLine node")
		return
	if arena.get_node_or_null("FallRespawn") == null:
		_fail("arena must have a FallRespawn node")
		return
	if arena.get_node_or_null("Rabbit") == null or arena.get_node_or_null("Fox") == null:
		_fail("arena must have Rabbit and Fox players")
		return
	if arena.race_mode == null:
		_fail("arena must initialize with a race_mode")
		return
	if arena.race_mode.is_finished():
		_fail("arena race_mode must start unfinished")
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
