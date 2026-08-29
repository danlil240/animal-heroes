class_name BubbleProjectile
extends Area2D

## One host-stepped harmless bubble. Instances are returned to ObjectPool after
## a hit or a bounded lifetime.

signal enemy_hit(enemy_id: String, owner_peer_id: int, projectile_id: String)
signal released(projectile: Node)

const SPEED: float = 360.0
const LIFETIME: float = 2.5
const BASIC: String = "basic"
const SPREAD: String = "spread"
const BASIC_VISUAL_SCALE := Vector2(0.42, 0.42)
const SPREAD_VISUAL_SCALE := Vector2(0.52, 0.52)
const SPREAD_TINT := Color("9ce7ff")

var active: bool = false
var owner_peer_id: int = 0
var projectile_id: String = ""
var projectile_kind: String = BASIC
var fan_index: int = 0
var velocity: Vector2 = Vector2.ZERO
var _remaining: float = 0.0


func _ready() -> void:
	area_entered.connect(_on_area_entered)
	reset_for_pool()


func launch(owner_id: int, origin: Vector2, shot_velocity: Variant, sequence: int, kind: String = BASIC, member_index: int = 0) -> bool:
	var resolved_velocity := _resolve_velocity(shot_velocity)
	if owner_id not in [1, 2] or sequence <= 0 or resolved_velocity.length_squared() < 1.0:
		return false
	if kind not in [BASIC, SPREAD] or member_index < -1 or member_index > 1:
		return false
	owner_peer_id = owner_id
	projectile_id = "bubble-%d-%d" % [sequence, member_index]
	projectile_kind = kind
	fan_index = member_index
	position = origin
	velocity = resolved_velocity
	_remaining = LIFETIME
	active = true
	visible = true
	monitoring = true
	monitorable = true
	_apply_appearance()
	return true


func host_step(delta: float) -> void:
	if not active:
		return
	var step := maxf(delta, 0.0)
	position += velocity * step
	_remaining = maxf(_remaining - step, 0.0)
	if _remaining <= 0.0:
		_finish()


func try_enemy_hit(enemy: Node) -> bool:
	if not active or enemy == null or not enemy.has_method("try_bubble"):
		return false
	if not bool(enemy.try_bubble(owner_peer_id)):
		return false
	var enemy_id := String(enemy.get("enemy_id"))
	enemy_hit.emit(enemy_id, owner_peer_id, projectile_id)
	_finish()
	return true


func reset_for_pool() -> void:
	active = false
	owner_peer_id = 0
	projectile_id = ""
	projectile_kind = BASIC
	fan_index = 0
	velocity = Vector2.ZERO
	_remaining = 0.0
	visible = false
	monitoring = false
	monitorable = false
	position = Vector2.ZERO
	_apply_appearance()


func lifetime_remaining() -> float:
	return _remaining


## Re-applies a snapshot entry from `SunnyForest.world_state_snapshot()` without
## going through `launch()`, so a reconnecting client can reconstruct in-flight
## projectiles at their authoritative mid-flight state.
func restore_state(payload: Dictionary) -> bool:
	var owner := int(payload.get("owner_peer_id", 0))
	var proj_id := String(payload.get("projectile_id", ""))
	var restored_kind := String(payload.get("projectile_kind", BASIC))
	var restored_fan_index := int(payload.get("fan_index", 0))
	if owner not in [1, 2] or proj_id.is_empty():
		return false
	if restored_kind not in [BASIC, SPREAD] or restored_fan_index < -1 or restored_fan_index > 1:
		return false
	owner_peer_id = owner
	projectile_id = proj_id
	projectile_kind = restored_kind
	fan_index = restored_fan_index
	position = Vector2(payload.get("position", Vector2.ZERO))
	velocity = Vector2(payload.get("velocity", Vector2.ZERO))
	_remaining = maxf(float(payload.get("remaining", 0.0)), 0.0)
	active = true
	visible = true
	monitoring = true
	monitorable = true
	_apply_appearance()
	return true


func _resolve_velocity(shot_velocity: Variant) -> Vector2:
	if shot_velocity is Vector2:
		return shot_velocity
	# The scalar direction remains temporarily valid for the existing level until
	# its fire authority moves to the Vector2-based powered-fire contract.
	if typeof(shot_velocity) == TYPE_INT or typeof(shot_velocity) == TYPE_FLOAT:
		var direction := float(shot_velocity)
		if absf(direction) < 0.001:
			return Vector2.ZERO
		return Vector2(signf(direction) * SPEED, 0.0)
	return Vector2.ZERO


func _apply_appearance() -> void:
	var visual := get_node_or_null("Visual") as Sprite2D
	if visual == null:
		return
	if projectile_kind == SPREAD:
		visual.modulate = SPREAD_TINT
		visual.scale = SPREAD_VISUAL_SCALE
	else:
		visual.modulate = Color.WHITE
		visual.scale = BASIC_VISUAL_SCALE


func _finish() -> void:
	if not active:
		return
	active = false
	visible = false
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	velocity = Vector2.ZERO
	if Engine.is_in_physics_frame():
		call_deferred("_emit_released")
	else:
		_emit_released()


func _emit_released() -> void:
	released.emit(self)


func _on_area_entered(area: Area2D) -> void:
	try_enemy_hit(area)
