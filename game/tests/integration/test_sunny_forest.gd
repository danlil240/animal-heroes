extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene = load("res://levels/sunny_forest.tscn")
	if scene == null:
		_fail("sunny forest scene must exist")
		return
	var level = scene.instantiate()
	root.add_child(level)
	await process_frame
	await physics_frame
	var spawns: Array = level.get_tree().get_nodes_in_group("player_spawn")
	if spawns.size() != 2:
		_fail("sunny forest must have exactly two player spawns, got %d" % spawns.size())
		return
	var checkpoints: Array = level.get_tree().get_nodes_in_group("checkpoint")
	if checkpoints.size() < 4:
		_fail("sunny forest must have at least four checkpoints, got %d" % checkpoints.size())
		return
	var collectibles: Array = level.get_tree().get_nodes_in_group("collectible")
	if collectibles.size() < 10:
		_fail("sunny forest must have at least ten collectibles, got %d" % collectibles.size())
		return
	var bubbles: Array = level.get_tree().get_nodes_in_group("bubble_powerup")
	if bubbles.size() < 1:
		_fail("sunny forest must have at least one bubble power-up")
		return
	var exit_node = level.get_node_or_null("Exit")
	if exit_node == null:
		_fail("sunny forest must have an Exit node")
		return
	if not "required_players" in exit_node or int(exit_node.get("required_players")) != 2:
		_fail("sunny forest Exit must require two players")
		return
	var enemies: Array = level.get_tree().get_nodes_in_group("enemy")
	if enemies.size() < 1:
		_fail("sunny forest must have at least one enemy")
		return
	level.queue_free()
	await process_frame
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
