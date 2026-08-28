class_name PlayerBody
extends CharacterBody2D

const PlayerInputScript = preload("res://player/player_input.gd")
const PlayerProfileScript = preload("res://player/player_profile.gd")
const PlayerStateScript = preload("res://player/player_state.gd")

const COYOTE_TIME: float = 0.10
const JUMP_BUFFER_TIME: float = 0.12
const DAMAGE_COOLDOWN: float = 0.75
const TIMER_EPSILON: float = 0.000001

@export var profile: PlayerProfileScript
@export var peer_id: int = 0
@export var gravity: float = 1200.0

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
var _last_damage_source_peer_id: int = 0
var _initialized: bool = false


func _ready() -> void:
	_ensure_initialized()
	_ensure_collision_shape()


func _physics_process(delta: float) -> void:
	physics_step(delta)


func apply_input(frame: PlayerInputScript.InputFrame) -> void:
	_ensure_initialized()
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
	var was_on_floor := is_on_floor()
	_damage_cooldown_remaining = _count_down(_damage_cooldown_remaining, step)
	if was_on_floor:
		_coyote_remaining = COYOTE_TIME
	_try_buffered_jump(was_on_floor or _coyote_remaining > 0.0)
	if not was_on_floor:
		_coyote_remaining = _count_down(_coyote_remaining, step)
		velocity.y += gravity * step
	_jump_buffer_remaining = _count_down(_jump_buffer_remaining, step)
	velocity.x = _input_axis * profile.move_speed
	move_and_slide()
	if is_on_floor():
		_coyote_remaining = COYOTE_TIME
		_try_buffered_jump(true)


func take_hit(source_peer_id: int) -> bool:
	_ensure_initialized()
	if _damage_cooldown_remaining > TIMER_EPSILON:
		return false
	_damage_cooldown_remaining = DAMAGE_COOLDOWN
	_last_damage_source_peer_id = source_peer_id
	hearts -= 1
	if hearts <= 0:
		respawn(checkpoint_position)
	return true


func respawn(at_position: Vector2) -> void:
	_ensure_initialized()
	checkpoint_position = at_position
	global_position = at_position
	velocity = Vector2.ZERO
	hearts = profile.max_hearts
	_input_axis = 0.0
	_jump_pressed = false
	_action_pressed = false
	_action_buffered = false
	_jump_buffer_remaining = 0.0
	_coyote_remaining = 0.0
	_damage_cooldown_remaining = 0.0
	_last_damage_source_peer_id = 0


func consume_action() -> bool:
	var was_buffered := _action_buffered
	_action_buffered = false
	return was_buffered


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
	state.input_axis = _input_axis
	state.jump_pressed = _jump_pressed
	state.action_pressed = _action_pressed
	state.action_buffered = _action_buffered
	state.jump_buffer_remaining = _jump_buffer_remaining
	state.coyote_remaining = _coyote_remaining
	state.damage_cooldown_remaining = _damage_cooldown_remaining
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
