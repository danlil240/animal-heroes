class_name BubbleProjectile
extends Area2D

## One host-stepped harmless bubble. Instances are returned to ObjectPool after
## a hit or a bounded lifetime.

signal enemy_hit(enemy_id: String, owner_peer_id: int, projectile_id: String)
signal released(projectile: Node)

const SPEED: float = 360.0
const LIFETIME: float = 2.5

var active: bool = false
var owner_peer_id: int = 0
var projectile_id: String = ""
var velocity: Vector2 = Vector2.ZERO
var _remaining: float = 0.0


func _ready() -> void:
	area_entered.connect(_on_area_entered)
	reset_for_pool()


func launch(owner_id: int, origin: Vector2, direction: float, sequence: int) -> bool:
	if owner_id <= 0 or sequence <= 0 or absf(direction) < 0.001:
		return false
	owner_peer_id = owner_id
	projectile_id = "bubble-%d" % sequence
	position = origin
	velocity = Vector2(signf(direction) * SPEED, 0.0)
	_remaining = LIFETIME
	active = true
	visible = true
	monitoring = true
	monitorable = true
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
	velocity = Vector2.ZERO
	_remaining = 0.0
	visible = false
	monitoring = false
	monitorable = false
	position = Vector2.ZERO


func _finish() -> void:
	if not active:
		return
	active = false
	visible = false
	monitoring = false
	monitorable = false
	velocity = Vector2.ZERO
	released.emit(self)


func _on_area_entered(area: Area2D) -> void:
	try_enemy_hit(area)
