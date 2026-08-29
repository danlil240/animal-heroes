class_name EnemyActor
extends Area2D

## Scene-level enemy motion, collision, and one-time defeat transition. Shared
## levels call host_step only on the authoritative peer.

signal defeated(enemy_id: String, peer_id: int)
signal hurt(enemy_id: String, peer_id: int)
signal player_hit(enemy_id: String, peer_id: int)

const WAIT := "wait"
const PATROL := "patrol"
const TELEGRAPH := "telegraph"
const HOP := "hop"
const HURT := "hurt"
const DEFEATED := "defeated"
const HURT_COOLDOWN: float = 0.16
const MAX_HIT_RECOIL: float = 180.0

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
@export_range(1, 9, 1) var max_health: int = 2

var motion_state: String = PATROL
var velocity: Vector2 = Vector2.ZERO
var health: int = 0
var hurt_remaining: float = 0.0

var _origin: Vector2 = Vector2.ZERO
var _direction: float = 1.0
var _state_elapsed: float = 0.0
var _defeat_emitted: bool = false
var _prior_motion_state: String = PATROL


func _init() -> void:
	body_entered.connect(_on_body_entered)


func _enter_tree() -> void:
	_ensure_health()


func _ready() -> void:
	if enemy_id.is_empty():
		enemy_id = name.to_snake_case()
	_origin = position
	motion_state = PATROL if enemy_kind == "beetle" else WAIT
	_prior_motion_state = motion_state
	_update_visual_state()


func configure(id: String, kind: String) -> void:
	enemy_id = id
	enemy_kind = kind
	motion_state = PATROL if enemy_kind == "beetle" else WAIT
	_prior_motion_state = motion_state


func host_step(delta: float) -> void:
	if motion_state == DEFEATED:
		return
	var step := maxf(delta, 0.0)
	if motion_state == HURT:
		_step_hurt(step)
		_update_visual_state()
		return
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


func try_bubble(peer_id: int, impulse: Vector2) -> bool:
	if motion_state in [DEFEATED, HURT] or peer_id <= 0:
		return false
	_ensure_health()
	health = maxi(health - 1, 0)
	if health == 0:
		return _defeat(peer_id)
	_prior_motion_state = motion_state
	motion_state = HURT
	hurt_remaining = HURT_COOLDOWN
	velocity = impulse.limit_length(MAX_HIT_RECOIL)
	hurt.emit(enemy_id, peer_id)
	_update_visual_state()
	return true


func snapshot_state() -> Dictionary:
	_ensure_health()
	return {
		"enemy_id": enemy_id,
		"enemy_kind": enemy_kind,
		"motion_state": motion_state,
		"health": health,
		"hurt_remaining": hurt_remaining,
		"position": position,
		"velocity": velocity,
		"direction": _direction,
		"prior_motion_state": _prior_motion_state,
	}


## Re-applies a snapshot entry from `SunnyForest.world_state_snapshot()` so a
## reconnecting client can reconstruct enemy motion and defeat state without
## re-emitting defeat signals.
func restore_state(payload: Dictionary) -> bool:
	var restored_id: Variant = payload.get("enemy_id")
	var restored_kind: Variant = payload.get("enemy_kind")
	var restored_state: Variant = payload.get("motion_state")
	var restored_health: Variant = payload.get("health")
	var restored_hurt_remaining: Variant = payload.get("hurt_remaining")
	var restored_position: Variant = payload.get("position")
	var restored_velocity: Variant = payload.get("velocity")
	var restored_direction: Variant = payload.get("direction")
	var restored_prior_state: Variant = payload.get("prior_motion_state")
	if not restored_id is String or String(restored_id) != enemy_id:
		return false
	if not restored_kind is String or String(restored_kind) != enemy_kind:
		return false
	if not restored_state is String or not restored_prior_state is String:
		return false
	if not restored_health is int or not _is_finite_number(restored_hurt_remaining):
		return false
	if not restored_position is Vector2 or not restored_velocity is Vector2 or not _is_finite_number(restored_direction):
		return false
	var state := String(restored_state)
	var prior_state := String(restored_prior_state)
	var next_health := int(restored_health)
	var next_hurt_remaining := float(restored_hurt_remaining)
	var next_position := restored_position as Vector2
	var next_velocity := restored_velocity as Vector2
	var next_direction := float(restored_direction)
	if state not in _valid_motion_states() or prior_state not in _normal_motion_states():
		return false
	if next_health < 0 or next_health > max_health or not next_position.is_finite() or not next_velocity.is_finite():
		return false
	if next_direction not in [-1.0, 1.0]:
		return false
	if state == DEFEATED and (next_health != 0 or not is_zero_approx(next_hurt_remaining)):
		return false
	if state == HURT and (next_health <= 0 or next_hurt_remaining <= 0.0 or next_hurt_remaining > HURT_COOLDOWN):
		return false
	if state not in [DEFEATED, HURT] and (next_health <= 0 or not is_zero_approx(next_hurt_remaining)):
		return false
	motion_state = state
	health = next_health
	hurt_remaining = next_hurt_remaining
	position = next_position
	velocity = next_velocity
	_direction = next_direction
	_prior_motion_state = prior_state
	_state_elapsed = 0.0
	_defeat_emitted = state == DEFEATED
	_set_collision_enabled(state != DEFEATED)
	_update_visual_state()
	return true


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


func _step_hurt(step: float) -> void:
	var hurt_step := minf(step, hurt_remaining)
	position += velocity * hurt_step
	hurt_remaining = maxf(hurt_remaining - hurt_step, 0.0)
	if hurt_remaining <= 0.0:
		velocity = Vector2.ZERO
		motion_state = _prior_motion_state
		_state_elapsed = 0.0


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


func _normal_motion_states() -> Array[String]:
	var states: Array[String] = []
	if enemy_kind == "beetle":
		states.append(PATROL)
	else:
		states.append_array([WAIT, TELEGRAPH, HOP])
	return states


func _valid_motion_states() -> Array[String]:
	var states := _normal_motion_states()
	states.append(HURT)
	states.append(DEFEATED)
	return states


func _is_finite_number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value))


func _ensure_health() -> void:
	if motion_state != DEFEATED and health <= 0:
		health = max_health
	else:
		health = clampi(health, 0, max_health)
