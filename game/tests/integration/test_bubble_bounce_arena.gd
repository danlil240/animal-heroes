extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var arena_scene = load("res://levels/bubble_bounce_arena.tscn")
	if arena_scene == null:
		_fail("bubble_bounce_arena.tscn must exist")
		return
	var arena = arena_scene.instantiate()
	root.add_child(arena)
	await process_frame
	await physics_frame
	var spawns: Array = arena.get_tree().get_nodes_in_group("player_spawn")
	if spawns.size() != 2:
		_fail("arena must have exactly 2 player spawns, got %d" % spawns.size())
		return
	var refill_zones: Array = arena.get_tree().get_nodes_in_group("bubble_refill")
	if refill_zones.size() < 2:
		_fail("arena must have at least 2 bubble refill zones, got %d" % refill_zones.size())
		return
	var platforms: Array = arena.get_tree().get_nodes_in_group("bb_platform")
	if platforms.size() < 3:
		_fail("arena must have at least 3 platforms, got %d" % platforms.size())
		return
	var walls: Array = arena.get_tree().get_nodes_in_group("bb_wall")
	if walls.size() < 2:
		_fail("arena must have at least 2 soft walls, got %d" % walls.size())
		return
	if arena.get_node_or_null("Rabbit") == null or arena.get_node_or_null("Fox") == null:
		_fail("arena must have Rabbit and Fox players")
		return
	if arena.get_node_or_null("Projectiles") == null:
		_fail("arena must have a Projectiles layer")
		return
	if arena.bounce_mode == null:
		_fail("arena must initialize with a bounce_mode")
		return
	if arena.bounce_mode.is_finished():
		_fail("arena bounce_mode must start unfinished")
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
