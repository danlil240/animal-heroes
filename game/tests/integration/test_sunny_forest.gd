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
	if not _test_platforms_are_reachable(level):
		return
	level.queue_free()
	await process_frame
	quit(0)


## Both heroes must be able to jump from the ground onto the lowest platform
## tier. The fox jumps lower than the rabbit, so it is the binding case: if its
## jump does not clear the first step the campaign is impassable on that tablet.
func _test_platforms_are_reachable(level: Node) -> bool:
	var ground_shape: CollisionShape2D = level.get_node("Ground/CollisionShape2D")
	var ground_top: float = ground_shape.global_position.y - (ground_shape.shape as RectangleShape2D).size.y * 0.5
	var lowest_step := INF
	for platform in level.get_tree().get_nodes_in_group("forest_platform"):
		var shape: CollisionShape2D = platform.get_node("CollisionShape2D")
		var top: float = shape.global_position.y - (shape.shape as RectangleShape2D).size.y * 0.5
		lowest_step = minf(lowest_step, ground_top - top)
	for hero_name in ["Rabbit", "Fox"]:
		var hero = level.get_node(hero_name)
		# Apex of a jump under constant gravity, measured from the rest pose.
		var reach: float = hero.profile.jump_speed * hero.profile.jump_speed / (2.0 * hero.gravity)
		if reach <= lowest_step:
			_fail("%s must be able to reach the lowest platform: jump reaches %.1f px, first step is %.1f px" % [
				hero_name, reach, lowest_step,
			])
			return false
	return true


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
