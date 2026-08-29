extends SceneTree

const STEP: float = 1.0 / 30.0

var _player_body_script: Script
var _player_input_script: Script


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_player_body_script = load("res://player/player_body.gd")
	_player_input_script = load("res://player/player_input.gd")
	if _player_body_script == null or _player_input_script == null:
		_fail("momentum movement requires the player body and input contracts")
		return
	root.add_child(_make_floor())
	await physics_frame
	if not _test_grounded_run_stop_reversal_and_stomp():
		return
	if not _test_jump_cut_height():
		return
	if not _test_air_acceleration_and_landing_snapshot():
		return
	quit(0)


## Catches instant horizontal movement, excessive stopping distance, reversal
## that skips braking, or stomps that do not launch the hero upward.
func _test_grounded_run_stop_reversal_and_stomp() -> bool:
	var body: PlayerBody = _make_grounded_body()
	if not _has_property(body.profile, &"max_run_speed"):
		_fail("player profiles must provide max_run_speed for momentum movement")
		return false
	var right = _frame(1.0)
	body.apply_input(right)
	for _tick in 11:
		body.physics_step(STEP)
	if body.velocity.x < body.profile.max_run_speed * 0.9:
		_fail("rabbit must reach 90 percent run speed within 0.35 seconds")
		return false
	var state: Variant = body.snapshot()
	if not is_equal_approx(state.run_speed_ratio, absf(body.velocity.x) / body.profile.max_run_speed):
		_fail("snapshot run speed ratio must describe the current horizontal velocity")
		return false

	var release_x: float = body.position.x
	body.apply_input(_frame())
	for _tick in 30:
		body.physics_step(STEP)
		if absf(body.velocity.x) < 0.01:
			break
	if body.position.x - release_x > 80.0:
		_fail("release stopping distance must stay within 80 pixels")
		return false

	body.apply_input(right)
	for _tick in 11:
		body.physics_step(STEP)
	body.apply_input(_frame(-1.0))
	body.physics_step(STEP)
	if body.velocity.x <= 0.0:
		_fail("reversal must brake the existing run before accelerating the other way")
		return false

	body.velocity.y = 100.0
	body.apply_stomp_rebound()
	if body.velocity.y >= -300.0:
		_fail("stomp rebound must launch upward")
		return false
	var beetle = load("res://world/beetle_enemy.tscn").instantiate()
	root.add_child(beetle)
	body.peer_id = 1
	body.global_position = beetle.global_position + Vector2(0.0, -24.0)
	body.velocity.y = 140.0
	beetle.emit_signal("body_entered", body)
	if body.velocity.y != -340.0:
		_fail("enemy stomps must use the player rebound contract")
		return false
	return true


## Catches a released jump using the same gravity as a held jump.
func _test_jump_cut_height() -> bool:
	var held_height := _jump_height(true)
	var tapped_height := _jump_height(false)
	if held_height < tapped_height * 1.25:
		_fail("held jump height must be at least 1.25 times the one-tick tap height")
		return false
	return true


## Catches air control matching grounded acceleration or landing state sticking
## around for more than the single air-to-floor physics step.
func _test_air_acceleration_and_landing_snapshot() -> bool:
	var grounded: PlayerBody = _make_grounded_body()
	grounded.apply_input(_frame(1.0))
	grounded.physics_step(STEP)
	var ground_speed: float = grounded.velocity.x

	var airborne: PlayerBody = _make_body(Vector2(420.0, 20.0))
	airborne.apply_input(_frame(1.0))
	airborne.physics_step(STEP)
	if airborne.velocity.x >= ground_speed:
		_fail("air acceleration must be lower than ground acceleration")
		return false

	var landing: PlayerBody = _make_body(Vector2(-420.0, 20.0))
	for _tick in 90:
		landing.physics_step(STEP)
		if landing.snapshot().just_landed:
			break
	if not landing.snapshot().just_landed:
		_fail("landing snapshot must mark the air-to-floor physics step")
		return false
	landing.physics_step(STEP)
	if landing.snapshot().just_landed:
		_fail("landing snapshot must clear after exactly one grounded physics step")
		return false
	return true


func _jump_height(hold_jump: bool) -> float:
	var body: PlayerBody = _make_grounded_body()
	body.apply_input(_frame(0.0, true))
	body.physics_step(STEP)
	if not hold_jump:
		body.apply_input(_frame())
	var start_y: float = body.position.y
	var peak_y: float = start_y
	for _tick in 90:
		body.physics_step(STEP)
		peak_y = minf(peak_y, body.position.y)
	return start_y - peak_y


func _make_grounded_body() -> PlayerBody:
	var body: PlayerBody = _make_body(Vector2(0.0, 166.0))
	body.physics_step(STEP)
	return body


func _make_body(at_position: Vector2) -> PlayerBody:
	var body = _player_body_script.new()
	body.profile = load("res://player/rabbit_profile.tres")
	body.position = at_position
	body.collision_layer = 0
	body.collision_mask = 1
	body.set_physics_process(false)
	root.add_child(body)
	return body as PlayerBody


func _make_floor() -> StaticBody2D:
	var floor := StaticBody2D.new()
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(2000.0, 20.0)
	collider.shape = shape
	floor.position = Vector2(0.0, 200.0)
	floor.add_child(collider)
	return floor


func _frame(axis: float = 0.0, jump: bool = false):
	var frame = _player_input_script.InputFrame.new()
	frame.axis = axis
	frame.jump = jump
	return frame


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _has_property(object: Object, property_name: StringName) -> bool:
	for property in object.get_property_list():
		if property.name == property_name:
			return true
	return false
