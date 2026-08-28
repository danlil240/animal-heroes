extends SceneTree


func _init() -> void:
	_test_object_pool_reuse()
	_test_powerup_expiry()
	_test_enemy_stomp()
	_test_interactable_host_authority()
	_test_coop_mode_checkpoint_confirmation()
	_test_invalid_remote_activation_rejected()
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


func _make_player_body(peer_id: int) -> Node:
	var player = load("res://player/player_body.gd").new()
	player.peer_id = peer_id
	player.profile = load("res://player/rabbit_profile.tres")
	root.add_child(player)
	return player


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
