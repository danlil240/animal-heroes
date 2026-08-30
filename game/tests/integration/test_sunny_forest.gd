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
	for section_name in ["SunlitMeadow", "CanopyFork", "FallenLogCrossing", "BubbleGrove", "MagicalTreeRun"]:
		if level.get_node_or_null(section_name) == null:
			_fail("sunny forest must expose section %s" % section_name)
			return
	var springs: Array = level.get_tree().get_nodes_in_group("spring_pad")
	if springs.size() < 3:
		_fail("sunny forest must have at least three springs, got %d" % springs.size())
		return
	var secrets: Array = level.get_tree().get_nodes_in_group("secret")
	if secrets.size() != 3:
		_fail("sunny forest must have exactly three secrets, got %d" % secrets.size())
		return
	if level.get_tree().get_nodes_in_group("safe_route").size() < 1:
		_fail("sunny forest must declare a nonempty safe route group")
		return
	if level.get_tree().get_nodes_in_group("fast_route").size() < 1:
		_fail("sunny forest must declare a nonempty fast route group")
		return
	if level.get_tree().get_nodes_in_group("bramble").size() < 1:
		_fail("sunny forest must include at least one breakable bramble")
		return
	if level.get_node_or_null("HUD/GameplayHud") == null:
		_fail("sunny forest must include the shared gameplay HUD")
		return
	if not _test_hud_renders_power_combo_and_secrets():
		return
	if not _test_platforms_are_reachable(level):
		return
	if not _test_projectile_hit_does_not_score_until_defeat(level):
		return
	if not _test_authoritative_star_and_enemy_score(level):
		return
	if not await _test_score_event_uses_host_combo_outcome():
		return
	if not await _test_first_teamwork_part_uses_host_combo_outcome():
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


## The HUD must render spread count, active combo, and secret progress, and
## hide power and combo when inactive.
func _test_hud_renders_power_combo_and_secrets() -> bool:
	var hud_scene = load("res://ui/gameplay_hud.tscn")
	var hud = hud_scene.instantiate()
	root.add_child(hud)
	hud.render(240, 2, 3, 7, 3, 2, 3)
	if hud.get_node("Power/Count").text != "7":
		_fail("spread count must render")
		hud.queue_free()
		return false
	if hud.get_node("Combo").text != "×3" or not hud.get_node("Combo").visible:
		_fail("active combo must render")
		hud.queue_free()
		return false
	if hud.get_node("Secrets").text != "2/3":
		_fail("secret progress must render")
		hud.queue_free()
		return false
	hud.render(240, 2, 3, 0, 1, 0, 3)
	if hud.get_node("Power").visible or hud.get_node("Combo").visible:
		_fail("inactive power and combo must hide")
		hud.queue_free()
		return false
	hud.queue_free()
	return true


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
	if level.register_enemy_defeat("beetle-meadow-1", 2) or level.team_score.total != 60:
		_fail("duplicate enemy defeat must not score twice")
		return false
	if level.team_combo.multiplier != 2:
		_fail("only the nonduplicate star and enemy scores must advance the combo")
		return false
	return true


## Catches a receiver previewing its own jittered combo timer instead of using
## the authoritative multiplier and resulting combo state carried by the event.
func _test_score_event_uses_host_combo_outcome() -> bool:
	var scene = load("res://levels/sunny_forest.tscn")
	var host = scene.instantiate()
	var receiver = scene.instantiate()
	root.add_child(host)
	root.add_child(receiver)
	await process_frame
	host.process_mode = Node.PROCESS_MODE_DISABLED
	receiver.process_mode = Node.PROCESS_MODE_DISABLED
	var payload: Dictionary = host._prepare_world_event("collect", {"target_id": "star-2"})
	if payload.get("score_multiplier", 0) != 1 or payload.get("combo_state", {}) != {"multiplier": 1, "remaining": 2.5}:
		_fail("host must carry its authoritative multiplier and resulting combo state")
		return false
	# Deliberately diverge receive-time state to the maximum active chain. The
	# identical host event must still award 10 and restore the host's 1x outcome.
	receiver.team_combo.commit_scored_event()
	receiver.team_combo.commit_scored_event()
	receiver.team_combo.commit_scored_event()
	receiver.team_combo.commit_scored_event()
	if not host.apply_world_event(1, "collect", payload) or not receiver.apply_world_event(1, "collect", payload):
		_fail("the same authoritative score event must apply on host and receiver")
		return false
	if host.team_score.total != 10 or receiver.team_score.total != 10:
		_fail("host and receiver must award the carried 1x score regardless of local timer")
		return false
	if host.team_combo.snapshot() != payload["combo_state"] or receiver.team_combo.snapshot() != payload["combo_state"]:
		_fail("host and receiver must apply the carried resulting combo state exactly")
		return false
	host.queue_free()
	receiver.queue_free()
	return true


## Catches the first accepted gate mutation scoring/refreshing without carrying
## the host's combo result, leaving a jittered receiver permanently divergent.
func _test_first_teamwork_part_uses_host_combo_outcome() -> bool:
	var scene = load("res://levels/sunny_forest.tscn")
	var host = scene.instantiate()
	var receiver = scene.instantiate()
	root.add_child(host)
	root.add_child(receiver)
	await process_frame
	host.process_mode = Node.PROCESS_MODE_DISABLED
	receiver.process_mode = Node.PROCESS_MODE_DISABLED
	host.team_combo.commit_scored_event()
	host.team_combo.commit_scored_event()
	host.team_combo.step(1.0)
	receiver.team_combo.commit_scored_event()
	receiver.team_combo.commit_scored_event()
	receiver.team_combo.commit_scored_event()
	receiver.team_combo.commit_scored_event()
	receiver.team_combo.step(2.4)
	var payload: Dictionary = host._prepare_world_event("gate_part", {
		"gate_id": "fallen-log",
		"part_id": "log",
		"peer_id": 2,
	})
	if payload.get("score_multiplier", 0) != 1 or payload.get("combo_state", {}) != {"multiplier": 2, "remaining": 2.5}:
		_fail("first accepted gate part must carry the host teamwork combo outcome")
		return false
	if not host.apply_world_event(1, "gate_part", payload) or not receiver.apply_world_event(1, "gate_part", payload):
		_fail("first valid gate part must be accepted on host and receiver")
		return false
	if host.team_score.total != 100 or receiver.team_score.total != 100:
		_fail("first accepted gate part must award teamwork exactly once on both peers")
		return false
	if host.team_combo.snapshot() != payload["combo_state"] or receiver.team_combo.snapshot() != payload["combo_state"]:
		_fail("first teamwork score must apply the carried combo refresh exactly")
		return false
	host.queue_free()
	receiver.queue_free()
	return true


## Catches an accepted non-lethal bubble hit being counted as an enemy defeat.
func _test_projectile_hit_does_not_score_until_defeat(level: Node) -> bool:
	var before: int = level.team_score.total
	level._on_bubble_enemy_hit("beetle-meadow-1", 1, "bubble-feedback-test")
	if level.team_score.total != before:
		_fail("non-lethal bubble hits must not award enemy defeat points")
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
	if not level.gate_is_open("fallen-log") or level.team_score.total != 160:
		_fail("two role actions must open the log gate and add 100 team points")
		return false
	if level.team_combo.multiplier != 2 or not is_equal_approx(level.team_combo.remaining, 2.5):
		_fail("teamwork must stay at 1x and only refresh the active combo window")
		return false
	return true


## Catches bubble pickup not granting ten, spread firing publishing a partial
## fan, or the active projectile budget growing beyond six.
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
	if level.active_bubble_count() != 3:
		_fail("context action with spread charges must fire a three-member fan")
		return false
	if level.bubble_ammo.remaining(1) != 9:
		_fail("one accepted spread sequence must consume exactly one charge")
		return false
	if not level.fire_bubble(1, Vector2(1800, 620), 1.0):
		_fail("a second complete spread fan must fit the remaining pool")
		return false
	if level.fire_bubble(1, Vector2(1800, 620), 1.0):
		_fail("spread fire must reject pool exhaustion atomically")
		return false
	if level.bubble_ammo.remaining(1) != 8 or level.active_bubble_count() != 6:
		_fail("two spread sequences must spend two charges and fill six projectile slots")
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
	if not level.gate_is_open("bubble-grove") or level.team_score.total != 260:
		_fail("pressure gate must award one 100-point teamwork bonus")
		return false
	var world_snapshot: Dictionary = level.world_state_snapshot()
	for required_key in ["score", "collected_ids", "combo", "checkpoint_id", "heroes", "enemies", "gates", "ammo", "projectiles", "event_sequence"]:
		if not world_snapshot.has(required_key):
			_fail("Sunny Forest reconnect snapshot is missing %s" % required_key)
			return false
	if world_snapshot.get("enemies", []).size() < 4 or world_snapshot.get("projectiles", []).size() != 6:
		_fail("snapshot must include enemy and active bubble world state")
		return false
	var enemy_snapshot: Dictionary = world_snapshot.get("enemies", [])[0]
	for required_enemy_key in ["enemy_id", "enemy_kind", "motion_state", "health", "hurt_remaining", "position", "velocity", "direction"]:
		if not enemy_snapshot.has(required_enemy_key):
			_fail("enemy snapshot must include durable state key %s" % required_enemy_key)
			return false
	level.register_enemy_defeat("after-snapshot", 1)
	level.grant_bubbles(1)
	if not level.restore_world_state(world_snapshot):
		_fail("valid Sunny Forest world snapshot must restore")
		return false
	if level.team_score.total != 260 or level.team_combo.multiplier != 2 or level.bubble_ammo.remaining(1) != 8 or level.active_bubble_count() != 6:
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
	if results.size() != 1 or int(results[0].get("team_score", -1)) != 260:
		_fail("finish payload must contain the authoritative team score")
		return false
	if String(results[0].get("next_level_id", "")) != "crystal_caves":
		_fail("Sunny Forest finish must unlock Crystal Caves")
		return false
	return true


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
