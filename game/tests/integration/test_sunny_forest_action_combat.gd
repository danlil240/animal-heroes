extends SceneTree

const PlayerInputScript := preload("res://player/player_input.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if not await _test_basic_held_fire_cadence():
		return
	if not await _test_interaction_claim_suppresses_fire_until_release():
		return
	if not await _test_remote_held_action_is_host_driven():
		return
	if not await _test_spread_is_atomic_and_consumes_one_charge():
		return
	if not await _test_offline_second_player_held_action_survives_physics_cleanup():
		return
	if not await _test_secret_discovery_awards_once_and_advances_combo():
		return
	quit(0)


## Catches basic fire requiring ammo, failing to fire immediately, or publishing
## more/fewer than five accepted sequences during one second of held input.
func _test_basic_held_fire_cadence() -> bool:
	var level = await _make_level()
	var rabbit = level.get_node("Rabbit")
	rabbit.global_position = Vector2(400, 640)
	rabbit.facing_direction = 1.0
	rabbit.apply_input(_frame(true))
	for tick in 20:
		level._step_level(0.05)
	if level.active_bubble_count() != 5:
		return _fail_bool("one second of held basic action must publish exactly five shots, got %d" % level.active_bubble_count())
	if level.bubble_ammo.remaining(1) != 0:
		return _fail_bool("unlimited basic fire must not create or consume spread charges")
	level.queue_free()
	await process_frame
	return true


## Catches a held interaction leaking shots either at the target or after moving
## away, and catches the claim surviving the release that should reset it.
func _test_interaction_claim_suppresses_fire_until_release() -> bool:
	var level = await _make_level()
	var fox = level.get_node("Fox")
	var log_target: Node2D = level.get_node("FallenLogCrossing/FallenLog")
	fox.global_position = log_target.global_position
	fox.apply_input(_frame(true))
	level._step_level(0.0)
	for tick in 5:
		level._step_level(0.1)
	var active_parts: Dictionary = level._gates["fallen-log"].snapshot().get("active_parts", {})
	if active_parts.size() != 1 or level.active_bubble_count() != 0:
		return _fail_bool("one held Fallen Log press must interact once and fire zero shots")
	fox.global_position = Vector2(400, 640)
	level._step_level(0.25)
	if level.active_bubble_count() != 0:
		return _fail_bool("an interaction claim must suppress firing until release even after moving away")
	fox.apply_input(_frame(false))
	level._step_level(0.0)
	fox.apply_input(_frame(true))
	level._step_level(0.0)
	if level.active_bubble_count() != 1:
		return _fail_bool("a new press away from interactables must fire immediately after release")
	level.queue_free()
	await process_frame
	return true


## Catches host fire authority looking only at the local hero and missing the
## replicated remote hero's held action state.
func _test_remote_held_action_is_host_driven() -> bool:
	var level = await _make_level()
	var fox = level.get_node("Fox")
	fox.apply_network_state(Vector2(400, 640), Vector2.ZERO, -1.0, false, true)
	level._step_level(0.0)
	if level.active_bubble_count() != 1:
		return _fail_bool("host must publish fire for replicated remote held action")
	var bubbles: Array = level.get_tree().get_nodes_in_group("active_bubble")
	if bubbles.size() != 1 or bubbles[0].owner_peer_id != 2 or bubbles[0].velocity != Vector2(-360.0, 0.0):
		return _fail_bool("remote held fire must preserve owner and facing direction")
	level.queue_free()
	await process_frame
	return true


## Catches disconnect cleanup treating a stale remote-input marker as proof of
## a live-peer transition and clearing ordinary offline second-player input
## before Sunny Forest can inspect it in the real physics cadence.
func _test_offline_second_player_held_action_survives_physics_cleanup() -> bool:
	var level = await _make_level()
	level.process_mode = Node.PROCESS_MODE_INHERIT
	var fox = level.get_node("Fox")
	fox.global_position = Vector2(400, 640)
	fox.facing_direction = 1.0
	fox.apply_input(_frame(true))
	level._has_remote_input = true
	level._had_live_world_peer = false
	level._physics_process(0.0)
	if level.active_bubble_count() != 1:
		return _fail_bool("offline second-player held input must survive cleanup until Sunny Forest inspects it")
	level.queue_free()
	await process_frame
	return true


## Catches spread publication exposing a partial fan or spending its charge
## before all three members have been acquired successfully.
func _test_spread_is_atomic_and_consumes_one_charge() -> bool:
	var level = await _make_level()
	var rabbit = level.get_node("Rabbit")
	rabbit.global_position = Vector2(400, 640)
	rabbit.facing_direction = 1.0
	level.grant_bubbles(1)
	rabbit.apply_input(_frame(true))
	level._step_level(0.0)
	var bubbles: Array = level.get_tree().get_nodes_in_group("active_bubble")
	if bubbles.size() != 3 or level.bubble_ammo.remaining(1) != 9:
		return _fail_bool("accepted spread sequence must publish three members and consume one charge")
	var fan_members: Dictionary = {}
	for bubble in bubbles:
		fan_members[bubble.fan_index] = bubble.velocity
	if fan_members != {-1: Vector2(360.0, -70.0), 0: Vector2(360.0, 0.0), 1: Vector2(360.0, 70.0)}:
		return _fail_bool("spread sequence must use the complete -70/0/70 velocity fan")
	_release_all_bubbles(level)
	# Leave five basic projectiles active. Only one slot remains, so the next
	# spread attempt must roll that partial acquisition back without spending.
	level.bubble_ammo = load("res://player/bubble_inventory.gd").new()
	for shot in 5:
		if not level.fire_bubble(2, Vector2(400, 640), 1.0):
			return _fail_bool("basic setup shot %d must be accepted" % shot)
	level.grant_bubbles(1)
	var charge_before: int = level.bubble_ammo.remaining(1)
	var sequence_before: int = level.last_world_event_sequence()
	var rejected: bool = level.publish_world_event("bubble_fire", {
		"peer_id": 1,
		"origin": Vector2(400, 640),
		"direction": 1.0,
	})
	if rejected:
		return _fail_bool("spread publication must report rejection when all three pool members are unavailable")
	if level.active_bubble_count() != 5 or level.bubble_ammo.remaining(1) != charge_before:
		return _fail_bool("failed spread must release partial members and preserve its charge")
	if level.last_world_event_sequence() != sequence_before or level._next_world_event_sequence != sequence_before:
		return _fail_bool("rejected spread must not advance or expose a client world-event sequence")
	level.queue_free()
	await process_frame
	return true


## A secret discovery must award score once, advance the combo, and reject a
## duplicate discovery of the same secret id.
func _test_secret_discovery_awards_once_and_advances_combo() -> bool:
	var level = await _make_level()
	var score_before: int = level.team_score.total
	if not level.discover_secret("test-secret", 1):
		return _fail_bool("first secret discovery must succeed")
	if level.discover_secret("test-secret", 2):
		return _fail_bool("duplicate secret discovery must be rejected")
	if level.discovered_secret_count() != 1:
		return _fail_bool("discovered secret count must be exactly one")
	if level.team_score.total <= score_before:
		return _fail_bool("secret discovery must award score")
	if level.team_combo.remaining <= 0.0:
		return _fail_bool("secret discovery must start the combo window")
	# A second distinct secret must receive the previewed multiplier.
	var preview_before: int = level.team_combo.preview_multiplier()
	if preview_before <= 1:
		return _fail_bool("combo preview must offer a multiplier after the first discovery")
	if not level.discover_secret("test-secret-2", 2):
		return _fail_bool("second distinct secret discovery must succeed")
	if level.team_combo.multiplier < preview_before:
		return _fail_bool("second secret discovery must commit the previewed combo multiplier")
	level.queue_free()
	await process_frame
	return true


func _make_level():
	var level = load("res://levels/sunny_forest.tscn").instantiate()
	root.add_child(level)
	await process_frame
	await physics_frame
	level.process_mode = Node.PROCESS_MODE_DISABLED
	return level


func _frame(action: bool):
	var frame := PlayerInputScript.InputFrame.new()
	frame.action = action
	return frame


func _release_all_bubbles(level: Node) -> void:
	var bubbles: Array = level.get_tree().get_nodes_in_group("active_bubble")
	for bubble in bubbles:
		level._on_bubble_released(bubble)


func _fail_bool(message: String) -> bool:
	push_error(message)
	quit(1)
	return false
