class_name Enemy
extends Node2D


signal defeated(peer_id: int)
signal hit_player(peer_id: int)

const PATROL := "patrol"
const STUNNED := "stunned"
const DEFEATED := "defeated"

@export var patrol_speed: float = 60.0
@export var patrol_range: float = 120.0
@export var stomp_window: float = 0.4
@export var damage_on_contact: bool = true

var state: String = PATROL
var _origin: Vector2 = Vector2.ZERO
var _direction: float = 1.0
var _stun_remaining: float = 0.0
var _defeat_emitted: bool = false


func _ready() -> void:
	_origin = global_position


func host_step(delta: float) -> void:
	var step := maxf(delta, 0.0)
	match state:
		PATROL:
			_patrol(step)
		STUNNED:
			_stun_remaining -= step
			if _stun_remaining <= 0.0:
				state = PATROL
		DEFEATED:
			pass


func try_stomp(stomp_position: Vector2, peer_id: int) -> bool:
	if state == DEFEATED:
		return false
	# A stomp is valid when the attacker is above the enemy and within horizontal range.
	if stomp_position.y >= global_position.y:
		return false
	if absf(stomp_position.x - global_position.x) > 40.0:
		return false
	state = DEFEATED
	if not _defeat_emitted:
		_defeat_emitted = true
		defeated.emit(peer_id)
	return true


func try_contact(player: Node) -> bool:
	if state == DEFEATED or not damage_on_contact:
		return false
	if player == null or not (player is CharacterBody2D):
		return false
	if not player.has_method("take_hit"):
		return false
	var hit: bool = player.take_hit(int(player.get_meta("peer_id", 0)))
	if hit:
		hit_player.emit(int(player.get_meta("peer_id", 0)))
	return hit


func reset() -> void:
	state = PATROL
	_stun_remaining = 0.0
	_defeat_emitted = false
	_direction = 1.0
	global_position = _origin


func _patrol(step: float) -> void:
	global_position.x += _direction * patrol_speed * step
	if absf(global_position.x - _origin.x) >= patrol_range:
		_direction *= -1.0
