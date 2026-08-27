extends SceneTree

var _player_input_script: Script
var _player_body_script: Script


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_player_input_script = load("res://player/player_input.gd")
	_player_body_script = load("res://player/player_body.gd")
	if _player_input_script == null or _player_body_script == null:
		_fail("player input and body contracts must exist")
		return
	var rabbit = load("res://player/rabbit_profile.tres")
	var fox = load("res://player/fox_profile.tres")
	var floor = _make_floor(0.0, 200.0, 240.0)
	root.add_child(floor)
	await physics_frame

	var rabbit_body = _make_player(rabbit, Vector2(500.0, 80.0))
	var fox_body = _make_player(fox, Vector2(700.0, 80.0))
	rabbit_body.apply_input(_frame(1.0))
	fox_body.apply_input(_frame(1.0))
	rabbit_body.physics_step(0.1)
	fox_body.physics_step(0.1)
	if not is_equal_approx(rabbit_body.position.x - 500.0, 8.0) or not is_equal_approx(fox_body.position.x - 700.0, 22.0 / 3.0):
		_fail("equal input must move rabbit 8 pixels and fox 22/3 pixels in one physics tick")
		return

	if not await _test_jump_and_landing(rabbit, -50.0):
		return
	if not await _test_jump_and_landing(fox, 50.0):
		return
	if not await _test_coyote_boundaries(rabbit):
		return
	if not await _test_jump_buffer_boundaries(rabbit):
		return
	if not _test_damage_and_respawn(rabbit):
		return
	quit(0)


func _test_jump_and_landing(profile: Resource, start_x: float) -> bool:
	var player = _make_player(profile, Vector2(start_x, 166.0))
	await physics_frame
	player.physics_step(0.0)
	player.apply_input(_frame(0.0, true))
	player.physics_step(0.0)
	player.apply_input(_frame())
	if player.velocity.y >= 0.0:
		_fail("a grounded player must launch upward when jump is pressed")
		return false
	for _tick in 90:
		player.physics_step(1.0 / 30.0)
	if not player.snapshot().grounded or player.velocity.y != 0.0:
		_fail("each hero must land after a jump")
		return false
	return true


func _test_coyote_boundaries(profile: Resource) -> bool:
	var inside = _make_player(profile, Vector2(0.0, 166.0))
	await physics_frame
	inside.physics_step(0.0)
	inside.position.x = 180.0
	inside.physics_step(0.0)
	inside.physics_step(0.099)
	inside.apply_input(_frame(0.0, true))
	inside.physics_step(0.0)
	if inside.velocity.y != -440.0:
		_fail("jump must work just inside the 0.10 second coyote window: velocity %s, coyote %s, grounded %s" % [inside.velocity.y, inside.snapshot().coyote_remaining, inside.snapshot().grounded])
		return false

	var at_limit = _make_player(profile, Vector2(0.0, 166.0))
	await physics_frame
	at_limit.physics_step(0.0)
	at_limit.position.x = 180.0
	at_limit.physics_step(0.0)
	at_limit.physics_step(0.1)
	at_limit.apply_input(_frame(0.0, true))
	at_limit.physics_step(0.0)
	if at_limit.velocity.y < 0.0:
		_fail("jump must expire at the 0.10 second coyote boundary")
		return false

	var outside = _make_player(profile, Vector2(0.0, 166.0))
	await physics_frame
	outside.physics_step(0.0)
	outside.position.x = 180.0
	outside.physics_step(0.0)
	outside.physics_step(0.101)
	outside.apply_input(_frame(0.0, true))
	outside.physics_step(0.0)
	if outside.velocity.y < 0.0:
		_fail("jump must stay unavailable just outside the coyote window")
		return false
	return true


func _test_jump_buffer_boundaries(profile: Resource) -> bool:
	var inside = _make_player(profile, Vector2(500.0, -400.0))
	await physics_frame
	inside.apply_input(_frame(0.0, true))
	var inside_buffer_after_press = inside.snapshot().jump_buffer_remaining
	inside.apply_input(_frame())
	inside.physics_step(0.119)
	var inside_buffer_before_landing = inside.snapshot().jump_buffer_remaining
	inside.position = Vector2(0.0, 166.0)
	inside.velocity = Vector2.ZERO
	inside.physics_step(0.0)
	if inside.velocity.y != -440.0:
		_fail("a jump pressed just inside the 0.12 second buffer must fire on landing: after press %s, before %s, velocity %s, buffer %s, grounded %s" % [inside_buffer_after_press, inside_buffer_before_landing, inside.velocity.y, inside.snapshot().jump_buffer_remaining, inside.snapshot().grounded])
		return false

	var at_limit = _make_player(profile, Vector2(500.0, -400.0))
	await physics_frame
	at_limit.apply_input(_frame(0.0, true))
	at_limit.apply_input(_frame())
	at_limit.physics_step(0.12)
	at_limit.position = Vector2(0.0, 166.0)
	at_limit.velocity = Vector2.ZERO
	at_limit.physics_step(0.0)
	if at_limit.velocity.y < 0.0:
		_fail("a jump pressed at the 0.12 second buffer boundary must expire")
		return false

	var outside = _make_player(profile, Vector2(500.0, -400.0))
	await physics_frame
	outside.apply_input(_frame(0.0, true))
	outside.apply_input(_frame())
	outside.physics_step(0.121)
	outside.position = Vector2(0.0, 166.0)
	outside.velocity = Vector2.ZERO
	outside.physics_step(0.0)
	if outside.velocity.y < 0.0:
		_fail("a jump pressed just outside the buffer must not fire on landing")
		return false
	return true


func _test_damage_and_respawn(profile: Resource) -> bool:
	var cooldown = _make_player(profile, Vector2(400.0, 80.0))
	if not cooldown.take_hit(11) or cooldown.snapshot().hearts != 2:
		_fail("an accepted hit must remove one heart")
		return false
	cooldown.physics_step(0.749)
	if cooldown.take_hit(12) or cooldown.snapshot().hearts != 2:
		_fail("damage must stay blocked just inside the 0.75 second cooldown")
		return false
	cooldown.physics_step(0.001)
	if not cooldown.take_hit(13) or cooldown.snapshot().hearts != 1:
		_fail("damage must be accepted at the 0.75 second cooldown boundary: cooldown %s" % cooldown.snapshot().damage_cooldown_remaining)
		return false

	var outside = _make_player(profile, Vector2(400.0, 80.0))
	outside.take_hit(21)
	outside.physics_step(0.751)
	if not outside.take_hit(22) or outside.snapshot().hearts != 1:
		_fail("damage must be accepted just outside the cooldown")
		return false

	var respawning = _make_player(profile, Vector2(400.0, 80.0))
	respawning.respawn(Vector2(75.0, 166.0))
	respawning.apply_input(_frame(1.0, true, true))
	respawning.take_hit(31)
	respawning.physics_step(0.75)
	respawning.take_hit(32)
	respawning.physics_step(0.75)
	respawning.take_hit(33)
	var state = respawning.snapshot()
	if state.position != Vector2(75.0, 166.0) or state.hearts != 3:
		_fail("a lethal hit must restore full hearts at the checkpoint")
		return false
	if state.velocity != Vector2.ZERO or state.jump_buffer_remaining != 0.0 or state.action_buffered or state.damage_cooldown_remaining != 0.0:
		_fail("respawn must clear stale movement, input, action, and damage state")
		return false
	respawning.physics_step(0.0)
	if respawning.velocity.y < 0.0:
		_fail("respawn must not auto-jump from an earlier jump press")
		return false
	if not respawning.take_hit(34) or respawning.snapshot().hearts != 2:
		_fail("respawn must clear the old damage cooldown")
		return false
	return true


func _make_player(profile: Resource, at_position: Vector2):
	var player = _player_body_script.new()
	player.profile = profile
	player.position = at_position
	root.add_child(player)
	player.set_physics_process(false)
	return player


func _make_floor(x: float, y: float, width: float) -> StaticBody2D:
	var floor = StaticBody2D.new()
	floor.position = Vector2(x, y)
	var collider = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(width, 20.0)
	collider.shape = shape
	floor.add_child(collider)
	return floor


func _frame(axis: float = 0.0, jump: bool = false, action: bool = false):
	var frame = _player_input_script.InputFrame.new()
	frame.axis = axis
	frame.jump = jump
	frame.action = action
	return frame


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
