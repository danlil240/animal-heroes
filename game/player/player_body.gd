class_name PlayerBody
extends CharacterBody2D

const PlayerInputScript = preload("res://player/player_input.gd")
const PlayerProfileScript = preload("res://player/player_profile.gd")
const PlayerStateScript = preload("res://player/player_state.gd")

const COYOTE_TIME: float = 0.10
const JUMP_BUFFER_TIME: float = 0.12
const STOMP_REBOUND_SPEED: float = 340.0
const DAMAGE_COOLDOWN: float = 0.75
const RESPAWN_DELAY: float = 1.0
const SPAWN_PROTECTION: float = 1.25
const TIMER_EPSILON: float = 0.000001

@export var profile: PlayerProfileScript
@export var peer_id: int = 0
@export var gravity: float = 1200.0

## When true, this body is driven by network state and skips local physics.
var is_network_remote: bool = false

var hearts: int = 0
var checkpoint_position: Vector2 = Vector2.ZERO
var facing_direction: float = 1.0

var _input_axis: float = 0.0
var _jump_pressed: bool = false
var _action_pressed: bool = false
var _action_buffered: bool = false
var _jump_buffer_remaining: float = 0.0
var _coyote_remaining: float = 0.0
var _damage_cooldown_remaining: float = 0.0
var _respawn_remaining: float = 0.0
var _spawn_protection_remaining: float = 0.0
var _pending_respawn_position: Vector2 = Vector2.ZERO
var _last_damage_source_peer_id: int = 0
var _just_landed: bool = false
var _initialized: bool = false


func _ready() -> void:
	_ensure_initialized()
	_ensure_collision_shape()


func _physics_process(delta: float) -> void:
	if is_network_remote:
		return
	physics_step(delta)


func apply_input(frame: PlayerInputScript.InputFrame) -> void:
	_ensure_initialized()
	if controls_locked():
		return
	_input_axis = clampf(frame.axis, -1.0, 1.0)
	if absf(_input_axis) > 0.01:
		facing_direction = signf(_input_axis)
	if frame.jump and not _jump_pressed:
		_jump_buffer_remaining = JUMP_BUFFER_TIME
	_jump_pressed = frame.jump
	if frame.action and not _action_pressed:
		_action_buffered = true
	_action_pressed = frame.action


func physics_step(delta: float) -> void:
	_ensure_initialized()
	var step := maxf(delta, 0.0)
	_just_landed = false
	_spawn_protection_remaining = _count_down(_spawn_protection_remaining, step)
	if _respawn_remaining > 0.0:
		_respawn_remaining = _count_down(_respawn_remaining, step)
		velocity = Vector2.ZERO
		if _respawn_remaining <= 0.0:
			_complete_delayed_respawn()
		return
	var was_on_floor := is_on_floor()
	_damage_cooldown_remaining = _count_down(_damage_cooldown_remaining, step)
	if was_on_floor:
		_coyote_remaining = COYOTE_TIME
	_try_buffered_jump(was_on_floor or _coyote_remaining > 0.0)
	if not was_on_floor:
		_coyote_remaining = _count_down(_coyote_remaining, step)
		velocity.y += gravity * step
	_jump_buffer_remaining = _count_down(_jump_buffer_remaining, step)
	var acceleration := profile.ground_acceleration if was_on_floor else profile.air_acceleration
	var target_speed := _input_axis * profile.max_run_speed
	if is_zero_approx(_input_axis):
		velocity.x = move_toward(velocity.x, 0.0, profile.ground_deceleration * step)
	else:
		velocity.x = move_toward(velocity.x, target_speed, acceleration * step)
	if not _jump_pressed and velocity.y < 0.0:
		velocity.y += gravity * (profile.jump_cut_gravity_multiplier - 1.0) * step
	move_and_slide()
	var is_now_on_floor := is_on_floor()
	_just_landed = not was_on_floor and is_now_on_floor
	if is_now_on_floor:
		_coyote_remaining = COYOTE_TIME
		_try_buffered_jump(true)


func apply_stomp_rebound() -> void:
	velocity.y = -STOMP_REBOUND_SPEED


func take_hit(source_peer_id: int) -> bool:
	return take_world_hit(source_peer_id, Vector2.ZERO)


func take_world_hit(source_peer_id: int, impulse: Vector2) -> bool:
	_ensure_initialized()
	if controls_locked() or _spawn_protection_remaining > TIMER_EPSILON or _damage_cooldown_remaining > TIMER_EPSILON:
		return false
	_damage_cooldown_remaining = DAMAGE_COOLDOWN
	_last_damage_source_peer_id = source_peer_id
	hearts -= 1
	velocity = impulse
	if hearts <= 0:
		begin_respawn(checkpoint_position)
	return true


func begin_respawn(at_position: Vector2) -> void:
	_ensure_initialized()
	_pending_respawn_position = at_position
	_respawn_remaining = RESPAWN_DELAY
	hearts = 0
	velocity = Vector2.ZERO
	_clear_transient_input()
	_damage_cooldown_remaining = 0.0


func controls_locked() -> bool:
	return _respawn_remaining > TIMER_EPSILON


func respawn(at_position: Vector2) -> void:
	_ensure_initialized()
	checkpoint_position = at_position
	global_position = at_position
	velocity = Vector2.ZERO
	hearts = profile.max_hearts
	_clear_transient_input()
	_damage_cooldown_remaining = 0.0
	_last_damage_source_peer_id = 0


func consume_action() -> bool:
	var was_buffered := _action_buffered
	_action_buffered = false
	return was_buffered


## Applies authoritative network state for a remote-controlled hero.
## Skips local physics; the owner's position and velocity are trusted directly.
func apply_network_state(pos: Vector2, vel: Vector2, axis: float, jump: bool, action: bool) -> void:
	_ensure_initialized()
	if absf(axis) > 0.01:
		facing_direction = signf(axis)
	global_position = pos
	velocity = vel
	_input_axis = axis
	_jump_pressed = jump
	_action_pressed = action


func snapshot() -> PlayerStateScript:
	_ensure_initialized()
	var state: PlayerStateScript = PlayerStateScript.new()
	state.peer_id = peer_id
	state.position = global_position
	state.velocity = velocity
	state.hearts = hearts
	state.max_hearts = profile.max_hearts
	state.can_push_heavy = profile.can_push_heavy
	state.grounded = is_on_floor()
	state.run_speed_ratio = absf(velocity.x) / profile.max_run_speed
	state.just_landed = _just_landed
	state.input_axis = _input_axis
	state.jump_pressed = _jump_pressed
	state.action_pressed = _action_pressed
	state.action_buffered = _action_buffered
	state.jump_buffer_remaining = _jump_buffer_remaining
	state.coyote_remaining = _coyote_remaining
	state.damage_cooldown_remaining = _damage_cooldown_remaining
	state.respawn_remaining = _respawn_remaining
	state.spawn_protection_remaining = _spawn_protection_remaining
	state.checkpoint_position = checkpoint_position
	state.last_damage_source_peer_id = _last_damage_source_peer_id
	return state


func _try_buffered_jump(can_jump: bool) -> void:
	if _jump_buffer_remaining > 0.0 and can_jump:
		velocity.y = -profile.jump_speed
		_jump_buffer_remaining = 0.0
		_coyote_remaining = 0.0


func _count_down(remaining: float, delta: float) -> float:
	var result := maxf(remaining - delta, 0.0)
	return 0.0 if result <= TIMER_EPSILON else result


func _complete_delayed_respawn() -> void:
	respawn(_pending_respawn_position)
	_spawn_protection_remaining = SPAWN_PROTECTION


func _clear_transient_input() -> void:
	_input_axis = 0.0
	_jump_pressed = false
	_action_pressed = false
	_action_buffered = false
	_jump_buffer_remaining = 0.0
	_coyote_remaining = 0.0


func _ensure_initialized() -> void:
	if _initialized:
		return
	if profile == null:
		profile = load("res://player/rabbit_profile.tres")
	hearts = profile.max_hearts
	checkpoint_position = global_position
	_initialized = true


func _ensure_collision_shape() -> void:
	for child in get_children():
		if child is CollisionShape2D:
			return
	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(32.0, 48.0)
	collision.shape = shape
	add_child(collision)
