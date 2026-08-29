class_name EnemyActor
extends Area2D

## Scene-level enemy motion, collision, and one-time defeat transition. Shared
## levels call host_step only on the authoritative peer.

signal defeated(enemy_id: String, peer_id: int)
signal player_hit(enemy_id: String, peer_id: int)

const WAIT := "wait"
const PATROL := "patrol"
const TELEGRAPH := "telegraph"
const HOP := "hop"
const DEFEATED := "defeated"

@export var enemy_id: String = ""
@export_enum("beetle", "seed") var enemy_kind: String = "beetle"
@export var patrol_speed: float = 60.0
@export var patrol_range: float = 120.0
@export var wait_duration: float = 1.0
@export var telegraph_duration: float = 0.35
@export var hop_horizontal_speed: float = 90.0
@export var hop_vertical_speed: float = 320.0
@export var hop_gravity: float = 900.0
@export var contact_impulse: Vector2 = Vector2(180.0, -220.0)

var motion_state: String = PATROL
var velocity: Vector2 = Vector2.ZERO

var _origin: Vector2 = Vector2.ZERO
var _direction: float = 1.0
var _state_elapsed: float = 0.0
var _defeat_emitted: bool = false


func _init() -> void:
	body_entered.connect(_on_body_entered)


func _ready() -> void:
	if enemy_id.is_empty():
		enemy_id = name.to_snake_case()
	_origin = position
	motion_state = PATROL if enemy_kind == "beetle" else WAIT
	_update_visual_state()


func configure(id: String, kind: String) -> void:
	enemy_id = id
	enemy_kind = kind
	motion_state = PATROL if enemy_kind == "beetle" else WAIT


func host_step(delta: float) -> void:
	if motion_state == DEFEATED:
		return
	var step := maxf(delta, 0.0)
	if enemy_kind == "seed":
		_step_seed(step)
	else:
		_step_beetle(step)
	_update_visual_state()


func try_contact(player: Node) -> bool:
	if motion_state == DEFEATED or player == null or not player.has_method("take_world_hit"):
		return false
	var horizontal := -1.0 if (player as Node2D).global_position.x < global_position.x else 1.0
	var impulse := Vector2(contact_impulse.x * horizontal, contact_impulse.y)
	var peer_id := int(player.get("peer_id"))
	if not bool(player.take_world_hit(0, impulse)):
		return false
	player_hit.emit(enemy_id, peer_id)
	return true


func try_stomp(hero_position: Vector2, hero_velocity: Vector2, peer_id: int) -> bool:
	if motion_state == DEFEATED or peer_id <= 0 or hero_velocity.y <= 0.0:
		return false
	if hero_position.y >= global_position.y or absf(hero_position.x - global_position.x) > 42.0:
		return false
	return _defeat(peer_id)


func try_bubble(peer_id: int) -> bool:
	if motion_state == DEFEATED or peer_id <= 0:
		return false
	return _defeat(peer_id)


## Re-applies a snapshot entry from `SunnyForest.world_state_snapshot()` so a
## reconnecting client can reconstruct enemy motion and defeat state without
## re-emitting defeat signals.
func restore_state(payload: Dictionary) -> void:
	var state := String(payload.get("motion_state", motion_state))
	motion_state = state
	position = Vector2(payload.get("position", position))
	velocity = Vector2(payload.get("velocity", velocity))
	_state_elapsed = 0.0
	_set_collision_enabled(state != DEFEATED)
	if state == DEFEATED:
		_defeat_emitted = true
	_update_visual_state()


func _step_beetle(step: float) -> void:
	var next_x := position.x + _direction * patrol_speed * step
	var left := _origin.x - patrol_range
	var right := _origin.x + patrol_range
	if next_x >= right:
		next_x = right
		_direction = -1.0
	elif next_x <= left:
		next_x = left
		_direction = 1.0
	position.x = next_x


func _step_seed(step: float) -> void:
	match motion_state:
		WAIT:
			_state_elapsed += step
			if _state_elapsed >= wait_duration:
				_set_motion_state(TELEGRAPH)
		TELEGRAPH:
			_state_elapsed += step
			if _state_elapsed >= telegraph_duration:
				velocity = Vector2(_direction * hop_horizontal_speed, -hop_vertical_speed)
				_set_motion_state(HOP)
		HOP:
			velocity.y += hop_gravity * step
			position += velocity * step
			if position.y >= _origin.y and velocity.y > 0.0:
				position.y = _origin.y
				velocity = Vector2.ZERO
				_direction *= -1.0
				_set_motion_state(WAIT)


func _set_motion_state(next_state: String) -> void:
	motion_state = next_state
	_state_elapsed = 0.0


func _defeat(peer_id: int) -> bool:
	if motion_state == DEFEATED:
		return false
	motion_state = DEFEATED
	velocity = Vector2.ZERO
	_set_collision_enabled(false)
	if not _defeat_emitted:
		_defeat_emitted = true
		defeated.emit(enemy_id, peer_id)
	_update_visual_state()
	return true


func _on_body_entered(body: Node2D) -> void:
	if not body is CharacterBody2D or not body.has_method("take_world_hit"):
		return
	var peer_id := int(body.get("peer_id"))
	if try_stomp(body.global_position, (body as CharacterBody2D).velocity, peer_id):
		if body.has_method("apply_stomp_rebound"):
			body.call("apply_stomp_rebound")
		else:
			(body as CharacterBody2D).velocity.y = -220.0
		return
	try_contact(body)


func _set_collision_enabled(enabled: bool) -> void:
	set_deferred("monitoring", enabled)
	set_deferred("monitorable", enabled)
	for child in get_children():
		if child is CollisionShape2D:
			(child as CollisionShape2D).set_deferred("disabled", not enabled)


func _update_visual_state() -> void:
	var visual := get_node_or_null("Visual")
	if visual != null and visual.has_method("show_enemy_state"):
		visual.show_enemy_state(motion_state, velocity, _direction)
