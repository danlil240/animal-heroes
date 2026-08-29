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
	if enemies.size() < 4:
		_fail("sunny forest must have at least four playable enemies")
		return
	var enemy_kinds: Dictionary = {}
	for enemy in enemies:
		enemy_kinds[String(enemy.get("enemy_kind"))] = true
	if not enemy_kinds.has("beetle") or not enemy_kinds.has("seed"):
		_fail("sunny forest must contain beetle and hopping-seed enemies")
		return
	for section_name in ["SunlitMeadow", "FallenLogCrossing", "BubbleGrove", "MagicalTreeFinish"]:
		if level.get_node_or_null(section_name) == null:
			_fail("sunny forest must expose section %s" % section_name)
			return
	if level.get_node_or_null("HUD/GameplayHud") == null:
		_fail("sunny forest must include the shared gameplay HUD")
		return
	if not _test_platforms_are_reachable(level):
		return
	if not _test_authoritative_star_and_enemy_score(level):
		return
	if not _test_role_gated_fallen_log(level):
		return
	if not _test_bubble_inventory_and_pool(level):
		return
	if not _test_pressure_gate_and_two_player_finish(level):
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


## Catches simultaneous collection or defeat events scoring more than once.
func _test_authoritative_star_and_enemy_score(level: Node) -> bool:
	var star = level.get_node("Collectibles/Star1")
	level.get_node("Rabbit").global_position = star.global_position
	if not level.process_world_action(1, 1, "collect", "star-1", star.global_position):
		_fail("host must accept an in-range star collection")
		return false
	if level.process_world_action(1, 2, "collect", "star-1", star.global_position):
		_fail("already-collected star must reject a second world action")
		return false
	if level.team_score.total != 10:
		_fail("one collected star must add exactly 10 team points")
		return false
	if not level.register_enemy_defeat("beetle-meadow-1", 1):
		_fail("first enemy defeat must be recorded")
		return false
	if level.register_enemy_defeat("beetle-meadow-1", 2) or level.team_score.total != 35:
		_fail("duplicate enemy defeat must not score twice")
		return false
	return true


## Catches either character bypassing the complementary-role teamwork gate.
func _test_role_gated_fallen_log(level: Node) -> bool:
	var log_target: Node2D = level.get_node("FallenLogCrossing/FallenLog")
	var switch_target: Node2D = level.get_node("FallenLogCrossing/OverheadSwitch")
	level.get_node("Rabbit").global_position = log_target.global_position
	if level.process_world_action(1, 3, "push", "fallen-log", log_target.global_position):
		_fail("Riki must not perform Foxy's heavy log push")
		return false
	level.get_node("Fox").global_position = log_target.global_position
	if not level.process_world_action(2, 1, "push", "fallen-log", log_target.global_position):
		_fail("Foxy must be able to push the fallen log")
		return false
	level.get_node("Fox").global_position = switch_target.global_position
	if level.process_world_action(2, 2, "switch", "overhead-switch", switch_target.global_position):
		_fail("Foxy must not perform Riki's overhead switch action")
		return false
	level.get_node("Rabbit").global_position = switch_target.global_position
	if not level.process_world_action(1, 4, "switch", "overhead-switch", switch_target.global_position):
		_fail("Riki must be able to activate the overhead switch")
		return false
	if not level.gate_is_open("fallen-log") or level.team_score.total != 135:
		_fail("two role actions must open the log gate and add 100 team points")
		return false
	return true


## Catches bubble pickup not granting ten, firing not consuming one, or the
## active projectile budget growing beyond six.
func _test_bubble_inventory_and_pool(level: Node) -> bool:
	if level.grant_bubbles(1) != 10:
		_fail("bubble flower must grant ten spread shots")
		return false
	var rabbit = level.get_node("Rabbit")
	rabbit.global_position = Vector2(400, 640)
	rabbit.facing_direction = 1.0
	var action_frame = load("res://player/player_input.gd").InputFrame.new()
	action_frame.action = true
	rabbit.apply_input(action_frame)
	level._step_level(0.0)
	if level.active_bubble_count() != 1:
		_fail("context action with no nearby object must fire a bubble")
		return false
	if level.bubble_ammo.remaining(1) != 9 or level.active_bubble_count() != 1:
		_fail("bubble fire must consume one shot and activate one projectile")
		return false
	for shot in 5:
		if not level.fire_bubble(1, Vector2(1800, 620), 1.0):
			_fail("remaining spread shot %d must fire" % shot)
			return false
	if level.bubble_ammo.remaining(1) != 4 or level.active_bubble_count() != 6:
		_fail("ten granted shots must leave four charges after six bounded projectiles")
		return false
	return true


## Catches one pressure flower opening the path or one hero finishing alone.
func _test_pressure_gate_and_two_player_finish(level: Node) -> bool:
	if level.activate_teamwork_part("bubble-grove", "left-flower", 1):
		_fail("one pressure flower must not complete Bubble Grove")
		return false
	if level.activate_teamwork_part("bubble-grove", "right-flower", 1):
		_fail("one hero must not complete both Bubble Grove pressure flowers")
		return false
	if not level.activate_teamwork_part("bubble-grove", "right-flower", 2):
		_fail("both pressure flowers must open Bubble Grove")
		return false
	if not level.gate_is_open("bubble-grove") or level.team_score.total != 235:
		_fail("pressure gate must award one 100-point teamwork bonus")
		return false
	var world_snapshot: Dictionary = level.world_state_snapshot()
	for required_key in ["score", "collected_ids", "checkpoint_id", "heroes", "enemies", "gates", "ammo", "projectiles", "event_sequence"]:
		if not world_snapshot.has(required_key):
			_fail("Sunny Forest reconnect snapshot is missing %s" % required_key)
			return false
	if world_snapshot.get("enemies", []).size() < 4 or world_snapshot.get("projectiles", []).size() != 6:
		_fail("snapshot must include enemy and active bubble world state")
		return false
	level.register_enemy_defeat("after-snapshot", 1)
	level.grant_bubbles(1)
	if not level.restore_world_state(world_snapshot):
		_fail("valid Sunny Forest world snapshot must restore")
		return false
	if level.team_score.total != 235 or level.bubble_ammo.remaining(1) != 4 or level.active_bubble_count() != 6:
		_fail("snapshot restore must replace score, ammo, and active projectiles")
		return false
	var results: Array[Dictionary] = []
	level.level_finished.connect(func(result: Dictionary) -> void: results.append(result))
	if level.enter_finish(1) or level.is_finished():
		_fail("one hero cannot finish the cooperative level alone")
		return false
	level.leave_finish(1)
	if level.enter_finish(2) or level.is_finished():
		_fail("heroes must be at the magical tree together, not one after another")
		return false
	if not level.enter_finish(1) or not level.is_finished():
		_fail("both heroes at the magical tree must finish the level")
		return false
	if results.size() != 1 or int(results[0].get("team_score", -1)) != 235:
		_fail("finish payload must contain the authoritative team score")
		return false
	if String(results[0].get("next_level_id", "")) != "crystal_caves":
		_fail("Sunny Forest finish must unlock Crystal Caves")
		return false
	return true


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
