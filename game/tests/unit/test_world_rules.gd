extends SceneTree


class TestInteraction extends Node2D:
	var interaction_id: String = ""
	var interaction_kind: String = "switch"
	var interaction_priority: int = 0
	var allowed: bool = true

	func eligible_for(_hero: Node) -> bool:
		return allowed


func _init() -> void:
	_test_object_pool_reuse()
	_test_powerup_expiry()
	_test_enemy_stomp()
	_test_interactable_host_authority()
	_test_coop_mode_checkpoint_confirmation()
	_test_invalid_remote_activation_rejected()
	_test_team_score_rejects_duplicate_events()
	_test_team_score_snapshot_round_trip()
	_test_bubble_inventory_tracks_powered_spread_shots()
	_test_action_resolver_prefers_high_priority_target()
	_test_action_resolver_rejects_ineligible_and_distant_targets()
	_test_action_resolver_uses_stable_tie_break()
	_test_interactable_character_eligibility()
	_test_beetle_actor_patrol_contact_and_stomp()
	_test_seed_actor_telegraphs_hops_and_accepts_bubble()
	_test_bubble_projectile_launch_move_hit_and_expire()
	_test_bubble_projectile_pool_is_bounded_and_resets()
	_test_teamwork_gate_requires_unique_known_parts()
	_test_teamwork_gate_snapshot_preserves_completion()
	quit(0)


func _test_object_pool_reuse() -> void:
	var pool_script = load("res://world/object_pool.gd")
	if pool_script == null:
		_fail("object pool must exist")
		return
	var pool = pool_script.new()
	pool.configure(preload("res://world/test_bubble.tscn"), 8)
	var first: Node = pool.acquire()
	if first == null:
		_fail("pool must return a node on acquire")
		return
	if pool.active_count() != 1:
		_fail("pool active count must reflect acquired node")
		return
	pool.release(first)
	if pool.active_count() != 0:
		_fail("pool active count must drop after release")
		return
	if pool.acquire() != first:
		_fail("pool did not reuse object")
		return
	# Bounded: acquiring beyond capacity returns null.
	var extra: Array[Node] = []
	for index in 7:
		var node: Node = pool.acquire()
		if node != null:
			extra.append(node)
	if pool.acquire() != null:
		_fail("pool exceeded configured capacity")
		return
	# Cleanup all acquired nodes.
	pool.release(first)
	for node in extra:
		pool.release(node)
	for node in extra:
		if is_instance_valid(node):
			node.queue_free()
	if is_instance_valid(first):
		first.queue_free()


func _test_powerup_expiry() -> void:
	var powerup_script = load("res://world/powerup.gd")
	if powerup_script == null:
		_fail("powerup must exist")
		return
	var powerup = powerup_script.new()
	powerup.duration = 1.0
	powerup.kind = "bubble"
	var player = _make_player_body(1)
	var hearts_before: int = player.hearts
	powerup.apply_to(player)
	if not player.has_meta("active_powerup") or player.get_meta("active_powerup") != "bubble":
		_fail("powerup must mark the player with its kind")
		return
	powerup.tick(0.5, player)
	if not powerup.is_active():
		_fail("powerup must remain active before duration elapses")
		return
	powerup.tick(0.6, player)
	if powerup.is_active():
		_fail("powerup must expire after duration elapses")
		return
	if player.get_meta("active_powerup", "") != "":
		_fail("powerup must clear the player marker on expiry")
		return
	if player.hearts != hearts_before:
		_fail("powerup must not change hearts on expiry")
		return
	if is_instance_valid(player):
		player.queue_free()
	if is_instance_valid(powerup):
		powerup.queue_free()


func _test_enemy_stomp() -> void:
	var enemy_script = load("res://world/enemy.gd")
	if enemy_script == null:
		_fail("enemy must exist")
		return
	var enemy = enemy_script.new()
	enemy.add_to_group("enemy")
	root.add_child(enemy)
	enemy.global_position = Vector2(100, 200)
	enemy.host_step(0.1)
	if enemy.state != enemy.PATROL:
		_fail("enemy must start in patrol state")
		return
	# A stomp from above defeats the enemy.
	var defeated: bool = enemy.try_stomp(Vector2(100, 180), 1)
	if not defeated or enemy.state != enemy.DEFEATED:
		_fail("stomp from above must defeat the enemy")
		return
	enemy.queue_free()


func _test_interactable_host_authority() -> void:
	var interactable_script = load("res://world/interactable.gd")
	if interactable_script == null:
		_fail("interactable must exist")
		return
	var interactable = interactable_script.new()
	interactable.add_to_group("switch")
	root.add_child(interactable)
	# Non-host peer cannot activate directly.
	var result: bool = interactable.try_activate(2, 1)
	if result or interactable.is_activated():
		_fail("non-host peer must not activate an interactable")
		return
	# Host peer activates.
	result = interactable.try_activate(1, 1)
	if not result or not interactable.is_activated():
		_fail("host peer must activate an interactable")
		return
	# Re-activation is rejected (already activated).
	result = interactable.try_activate(1, 1)
	if result:
		_fail("interactable must not re-activate once active")
		return
	interactable.queue_free()


func _test_coop_mode_checkpoint_confirmation() -> void:
	var mode_script = load("res://modes/coop_mode.gd")
	if mode_script == null:
		_fail("coop mode must exist")
		return
	var mode = mode_script.new()
	mode.start("sunny_forest", ["sunny_forest"])
	if mode.current_checkpoint_id != "":
		_fail("coop mode must start without a confirmed checkpoint")
		return
	mode.confirm_checkpoint("cp-1")
	if mode.current_checkpoint_id != "cp-1" or not mode.unlocked_levels.has("sunny_forest"):
		_fail("coop mode must record the confirmed checkpoint id")
		return
	# Duplicate confirmation is ignored.
	mode.confirm_checkpoint("cp-1")
	if mode.confirmation_count != 1:
		_fail("coop mode must not double-count duplicate checkpoints")
		return


func _test_invalid_remote_activation_rejected() -> void:
	var interactable_script = load("res://world/interactable.gd")
	if interactable_script == null:
		_fail("interactable must exist")
		return
	var interactable = interactable_script.new()
	interactable.add_to_group("switch")
	interactable.cooldown = 0.5
	root.add_child(interactable)
	# Out-of-range activation is rejected.
	interactable.try_activate(1, 1)
	interactable.reset()
	interactable.global_position = Vector2(0, 0)
	var player = _make_player_body(1)
	player.global_position = Vector2(500, 0)
	var validated: bool = interactable.validate_proximity(player, 100.0)
	if validated:
		_fail("out-of-range activation must be rejected")
		return
	player.global_position = Vector2(50, 0)
	validated = interactable.validate_proximity(player, 100.0)
	if not validated:
		_fail("in-range activation must be accepted")
		return
	interactable.queue_free()
	player.queue_free()


## Catches a repeated overlap or replayed world event awarding points twice.
func _test_team_score_rejects_duplicate_events() -> void:
	var score_script = load("res://core/team_score.gd")
	if score_script == null:
		_fail("team score rules must exist")
		return
	var score = score_script.new()
	if score.award("star-1", "star") != 10:
		_fail("first star must add exactly 10")
		return
	if score.award("star-1", "star") != 0 or score.total != 10:
		_fail("duplicate event ids must not score twice")
		return
	if score.award("enemy-1", "enemy") != 25:
		_fail("enemy must add exactly 25")
		return
	if score.award("gate-1", "teamwork") != 100 or score.total != 135:
		_fail("teamwork must add exactly 100")
		return
	if score.award("unknown-1", "unknown") != 0 or score.total != 135:
		_fail("unknown score categories must not change the total")


## Catches reconnect restoration losing the total or duplicate-event history.
func _test_team_score_snapshot_round_trip() -> void:
	var score_script = load("res://core/team_score.gd")
	if score_script == null:
		_fail("team score rules must exist")
		return
	var original = score_script.new()
	original.award("star-1", "star")
	original.award("enemy-1", "enemy")
	var restored = score_script.new()
	if not restored.restore(original.snapshot()) or restored.total != 35:
		_fail("score snapshot must round trip")
		return
	if restored.award("enemy-1", "enemy") != 0 or restored.total != 35:
		_fail("restored score must retain duplicate-event history")
		return
	if restored.restore({"total": -1, "awarded_ids": []}):
		_fail("negative restored totals must be rejected")


## Catches a bubble flower granting unbounded shots or empty ammo still firing.
func _test_bubble_inventory_tracks_powered_spread_shots() -> void:
	var inventory_script = load("res://player/bubble_inventory.gd")
	if inventory_script == null:
		_fail("bubble inventory rules must exist")
		return
	var inventory = inventory_script.new()
	if inventory.kind(1) != "basic" or inventory.remaining(1) != 0:
		_fail("heroes must start with unlimited basic fire")
		return
	if inventory.grant_spread(1) != 10 or inventory.kind(1) != "spread":
		_fail("bubble flower must grant ten spread shots")
		return
	if inventory.grant_spread(1, 50) != 10:
		_fail("spread charges must clamp at ten")
		return
	for index in 10:
		if not inventory.consume_spread(1):
			_fail("spread shot %d must be consumable" % index)
			return
	if inventory.consume_spread(1) or inventory.kind(1) != "basic" or inventory.remaining(1) != 0:
		_fail("exhausted spread charges must return to unlimited basic fire")
		return
	if inventory.grant(1) != 10 or inventory.consume(1) == false or inventory.remaining(1) != 9:
		_fail("legacy grant and consume wrappers must follow the ten-charge spread contract")
		return
	var restored = inventory_script.new()
	if not restored.restore({1: {"kind": "spread", "remaining": 4}, 2: {"kind": "basic", "remaining": 0}}):
		_fail("valid bubble inventory snapshot must restore")
		return
	if restored.kind(1) != "spread" or restored.remaining(1) != 4 or restored.kind(2) != "basic":
		_fail("bubble inventory snapshot must preserve powered kind and count")
		return
	var json_restored = inventory_script.new()
	if not json_restored.restore({"1": {"kind": "spread", "remaining": 2}}) or json_restored.kind(1) != "spread" or json_restored.remaining(1) != 2:
		_fail("inventory restore must accept numeric peer keys after JSON round-trip")
		return
	var before: Dictionary = restored.snapshot()
	if restored.restore({1: {"kind": "laser", "remaining": 1}}):
		_fail("unknown powered inventory kinds must be rejected")
		return
	if restored.restore({3: {"kind": "spread", "remaining": 1}}):
		_fail("inventory restore must reject peers outside the two heroes")
		return
	if restored.restore({1: {"kind": "spread", "remaining": 11}}):
		_fail("inventory restore must reject counts above ten")
		return
	if restored.restore({1: {"kind": "spread", "remaining": 1}, "1": {"kind": "spread", "remaining": 2}}):
		_fail("inventory restore must reject duplicate normalized peer entries")
		return
	if restored.snapshot() != before:
		_fail("failed inventory restore must leave existing charges unchanged")


## Catches bubble firing while a nearby teamwork object should own the action.
func _test_action_resolver_prefers_high_priority_target() -> void:
	var resolver_script = load("res://player/action_resolver.gd")
	if resolver_script == null:
		_fail("action resolver must exist")
		return
	var hero := Node2D.new()
	root.add_child(hero)
	var bubble := _make_interaction("bubble", 10, Vector2(20, 0))
	var gate := _make_interaction("gate", 100, Vector2(80, 0))
	if resolver_script.new().select(hero, [bubble, gate]) != gate:
		_fail("higher priority nearby teamwork target must beat bubble")


## Catches activation of an object the hero cannot use or can no longer reach.
func _test_action_resolver_rejects_ineligible_and_distant_targets() -> void:
	var resolver_script = load("res://player/action_resolver.gd")
	if resolver_script == null:
		_fail("action resolver must exist")
		return
	var hero := Node2D.new()
	root.add_child(hero)
	var blocked := _make_interaction("blocked", 100, Vector2(20, 0))
	blocked.allowed = false
	var distant := _make_interaction("distant", 100, Vector2(200, 0))
	var bubble := _make_interaction("bubble", 10, Vector2(40, 0))
	if resolver_script.new().select(hero, [blocked, distant, bubble]) != bubble:
		_fail("resolver must ignore ineligible and out-of-range targets")


## Catches peer order changing which equal-distance target is selected.
func _test_action_resolver_uses_stable_tie_break() -> void:
	var resolver_script = load("res://player/action_resolver.gd")
	if resolver_script == null:
		_fail("action resolver must exist")
		return
	var hero := Node2D.new()
	root.add_child(hero)
	var first := _make_interaction("a", 50, Vector2(30, 0))
	var second := _make_interaction("b", 50, Vector2(-30, 0))
	var resolver = resolver_script.new()
	if resolver.select(hero, [second, first]) != first:
		_fail("equal targets must use stable interaction id order")
		return
	if resolver.select(hero, [first, second]) != first:
		_fail("candidate array order must not affect target selection")


## Catches Foxy's push target being offered to Riki, or Riki's switch being
## offered to Foxy after the scene is replicated on the other tablet.
func _test_interactable_character_eligibility() -> void:
	var interactable = load("res://world/interactable.gd").new()
	root.add_child(interactable)
	var rabbit = _make_player_body(1)
	var fox = _make_player_body(2)
	fox.profile = load("res://player/fox_profile.tres")
	interactable.required_character = "fox"
	if interactable.eligible_for(rabbit) or not interactable.eligible_for(fox):
		_fail("fox-only interaction must reject rabbit and accept fox")
		return
	interactable.required_character = "rabbit"
	if not interactable.eligible_for(rabbit) or interactable.eligible_for(fox):
		_fail("rabbit-only interaction must accept rabbit and reject fox")


## Catches the beetle walking beyond its safe platform, contact doing nothing,
## or one stomp awarding multiple defeat transitions.
func _test_beetle_actor_patrol_contact_and_stomp() -> void:
	var scene: PackedScene = load("res://world/beetle_enemy.tscn")
	if scene == null:
		_fail("beetle enemy scene must load")
		return
	var beetle = scene.instantiate()
	beetle.patrol_range = 20.0
	beetle.patrol_speed = 100.0
	root.add_child(beetle)
	beetle.host_step(0.3)
	if absf(beetle.position.x) > 20.0:
		_fail("beetle patrol must stay inside its configured range")
		return
	var player = _make_player_body(1)
	var hearts_before: int = player.snapshot().hearts
	var contact_result: bool = beetle.try_contact(player)
	if not contact_result or player.hearts != hearts_before - 1:
		_fail("beetle contact must damage a vulnerable hero: result=%s before=%d after=%d locked=%s cooldown=%.3f spawn=%.3f" % [
			contact_result,
			hearts_before,
			player.hearts,
			player.controls_locked(),
			player.snapshot().damage_cooldown_remaining,
			player.snapshot().spawn_protection_remaining,
		])
		return
	if player.velocity.y >= 0.0:
		_fail("beetle contact must knock the hero upward")
		return
	var emissions: Array[int] = []
	beetle.defeated.connect(func(_enemy_id: String, peer_id: int) -> void: emissions.append(peer_id))
	if not beetle.try_stomp(beetle.global_position + Vector2(0, -24), Vector2(0, 140), 1):
		_fail("descending stomp from above must defeat beetle")
		return
	if beetle.try_stomp(beetle.global_position + Vector2(0, -24), Vector2(0, 140), 1):
		_fail("defeated beetle must reject repeated stomps")
		return
	if emissions != [1]:
		_fail("beetle defeat must emit exactly once")
		return
	var collision_beetle = scene.instantiate()
	root.add_child(collision_beetle)
	var falling_player = _make_player_body(1)
	falling_player.snapshot()
	falling_player.global_position = collision_beetle.global_position + Vector2(0, -24)
	falling_player.velocity = Vector2(0, 140)
	collision_beetle.emit_signal("body_entered", falling_player)
	if collision_beetle.motion_state != collision_beetle.DEFEATED:
		_fail("enemy body overlap must route a descending hero to stomp logic")


## Catches the seed jumping without warning or bubbles failing to defeat it.
func _test_seed_actor_telegraphs_hops_and_accepts_bubble() -> void:
	var scene: PackedScene = load("res://world/seed_enemy.tscn")
	if scene == null:
		_fail("seed enemy scene must load")
		return
	var seed = scene.instantiate()
	seed.configure("seed-test", "seed")
	root.add_child(seed)
	seed.host_step(seed.wait_duration)
	if seed.motion_state != seed.TELEGRAPH:
		_fail("seed must visibly telegraph before hopping: state=%s elapsed_wait=%.3f configured_wait=%.3f" % [
			seed.motion_state, seed.get("_state_elapsed"), seed.wait_duration,
		])
		return
	seed.host_step(seed.telegraph_duration * 0.5)
	if seed.motion_state != seed.TELEGRAPH:
		_fail("seed telegraph must remain visible for its full duration")
		return
	seed.host_step(seed.telegraph_duration * 0.5)
	if seed.motion_state != seed.HOP or seed.velocity.y >= 0.0:
		_fail("seed hop must begin with upward velocity after telegraph")
		return
	if not seed.try_bubble(2) or seed.motion_state != seed.DEFEATED:
		_fail("one bubble hit must defeat the hopping seed")
		return
	if seed.try_bubble(2):
		_fail("defeated seed must reject repeated bubble hits")


## Catches invalid shots becoming active, projectile motion drifting from the
## host rule, bubbles damaging heroes, or one bubble hitting twice.
func _test_bubble_projectile_launch_move_hit_and_expire() -> void:
	var scene: PackedScene = load("res://world/bubble_projectile.tscn")
	if scene == null:
		_fail("bubble projectile scene must load")
		return
	var bubble = scene.instantiate()
	root.add_child(bubble)
	if bubble.launch(0, Vector2.ZERO, Vector2(360.0, 0.0), 1):
		_fail("bubble must reject invalid owner peer id")
		return
	if bubble.launch(1, Vector2.ZERO, Vector2.ZERO, 1):
		_fail("bubble must reject zero velocity")
		return
	if bubble.launch(1, Vector2.ZERO, 0.0001, 1):
		_fail("legacy scalar launch must reject a near-zero direction")
		return
	if not bubble.launch(1, Vector2(10, 20), Vector2(360.0, -40.0), 7, "spread", -1):
		_fail("valid bubble launch must become active")
		return
	if bubble.projectile_kind != "spread" or bubble.fan_index != -1 or bubble.projectile_id != "bubble-7--1":
		_fail("spread member must preserve its distinct kind and fan identity")
		return
	var spread_visual := bubble.get_node("Visual") as Sprite2D
	if spread_visual.scale != Vector2(0.52, 0.52) or spread_visual.modulate != Color("9ce7ff"):
		_fail("spread members must have a distinct tint and scale")
		return
	bubble.host_step(0.5)
	if bubble.position != Vector2(190, 0):
		_fail("bubble must move from its supplied velocity")
		return
	var player = _make_player_body(2)
	if bubble.try_enemy_hit(player):
		_fail("bubble projectile must never damage a hero")
		return
	var seed = load("res://world/seed_enemy.tscn").instantiate()
	seed.configure("seed-hit", "seed")
	root.add_child(seed)
	var hits: Array[String] = []
	bubble.enemy_hit.connect(func(enemy_id: String, owner_id: int, projectile_id: String) -> void:
		hits.append("%s:%d:%s" % [enemy_id, owner_id, projectile_id]))
	if not bubble.try_enemy_hit(seed):
		_fail("active bubble must defeat an enemy that accepts bubble hits")
		return
	if bubble.try_enemy_hit(seed) or hits != ["seed-hit:1:bubble-7--1"]:
		_fail("bubble must emit one enemy hit and then become inactive")
		return
	bubble.reset_for_pool()
	if bubble.projectile_kind != "basic" or bubble.fan_index != 0 or spread_visual.scale != Vector2(0.42, 0.42) or spread_visual.modulate != Color.WHITE:
		_fail("pool reset must restore the basic bubble identity and appearance")
		return
	var releases: Array[int] = []
	bubble.released.connect(func(_node: Node) -> void: releases.append(1))
	bubble.launch(1, Vector2.ZERO, Vector2(-360.0, 0.0), 8)
	bubble.host_step(2.499)
	if not bubble.active or not releases.is_empty():
		_fail("bubble must remain active just inside its 2.5 second lifetime")
		return
	bubble.host_step(0.001)
	if bubble.active or releases.size() != 1:
		_fail("bubble must release exactly at its lifetime boundary")
		return
	var restored_bubble = scene.instantiate()
	root.add_child(restored_bubble)
	if not restored_bubble.restore_state({
		"owner_peer_id": 2,
		"projectile_id": "bubble-9-1",
		"position": Vector2(40.0, 20.0),
		"velocity": Vector2(-360.0, 0.0),
		"remaining": 1.0,
		"projectile_kind": "spread",
		"fan_index": 1,
	}):
		_fail("projectile restore must accept a valid powered spread member")
		return
	if restored_bubble.projectile_kind != "spread" or restored_bubble.fan_index != 1:
		_fail("projectile restore must preserve powered kind and fan identity")


## Catches the level exceeding six simultaneous bubbles or a pooled projectile
## retaining old owner/collision state when reused.
func _test_bubble_projectile_pool_is_bounded_and_resets() -> void:
	var pool = load("res://world/object_pool.gd").new()
	pool.configure(load("res://world/bubble_projectile.tscn"), 6)
	var acquired: Array[Node] = []
	for index in 6:
		var bubble: Node = pool.acquire()
		if bubble == null:
			_fail("pool must provide each of its six bubble slots")
			return
		bubble.launch(1, Vector2.ZERO, Vector2(360.0, 0.0), index + 1)
		acquired.append(bubble)
	if pool.acquire() != null:
		_fail("bubble pool must reject a seventh simultaneous projectile")
		return
	var first: Node = acquired[0]
	pool.release(first)
	if first.active or first.visible or first.projectile_kind != "basic" or first.fan_index != 0:
		_fail("released bubble must clear active state and powered identity")
		return
	if pool.acquire() != first:
		_fail("bubble pool must reuse the released projectile")


## Catches one hero repeating the same action to complete a two-part gate, or
## an unknown scene target advancing progress.
func _test_teamwork_gate_requires_unique_known_parts() -> void:
	var gate_script = load("res://world/teamwork_gate.gd")
	if gate_script == null:
		_fail("teamwork gate rules must exist")
		return
	var gate = gate_script.new()
	gate.configure("fallen-log", ["log", "overhead-switch"])
	var completions: Array[String] = []
	gate.completed.connect(func(gate_id: String) -> void: completions.append(gate_id))
	if gate.mark_part("unknown", 1):
		_fail("unknown teamwork part must be rejected")
		return
	if gate.mark_part("log", 2):
		_fail("first of two teamwork parts must not complete the gate")
		return
	if gate.mark_part("log", 2):
		_fail("duplicate teamwork part must be rejected")
		return
	if not gate.mark_part("overhead-switch", 1) or not gate.is_complete():
		_fail("two unique known parts must complete the gate")
		return
	if gate.mark_part("overhead-switch", 1) or completions != ["fallen-log"]:
		_fail("completed teamwork gate must emit exactly once")


## Catches reconnect reopening a completed gate or forgetting a partial gate.
func _test_teamwork_gate_snapshot_preserves_completion() -> void:
	var gate_script = load("res://world/teamwork_gate.gd")
	if gate_script == null:
		_fail("teamwork gate rules must exist")
		return
	var original = gate_script.new()
	original.configure("pressure-flowers", ["left", "right"])
	original.mark_part("left", 1)
	var partial = gate_script.new()
	partial.configure("pressure-flowers", ["left", "right"])
	if not partial.restore(original.snapshot()) or partial.is_complete():
		_fail("partial teamwork snapshot must restore without completing")
		return
	if not partial.mark_part("right", 2):
		_fail("restored partial gate must accept its missing part")
		return
	var complete = gate_script.new()
	complete.configure("pressure-flowers", ["left", "right"])
	if not complete.restore(partial.snapshot()) or not complete.is_complete():
		_fail("completed teamwork snapshot must remain open after restore")


func _make_interaction(id: String, priority: int, at_position: Vector2) -> TestInteraction:
	var interaction := TestInteraction.new()
	interaction.interaction_id = id
	interaction.interaction_priority = priority
	interaction.position = at_position
	root.add_child(interaction)
	return interaction


func _make_player_body(peer_id: int) -> Node:
	var player = load("res://player/player_body.gd").new()
	player.peer_id = peer_id
	player.profile = load("res://player/rabbit_profile.tres")
	root.add_child(player)
	return player


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
