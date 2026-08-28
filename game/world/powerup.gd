class_name Powerup
extends Area2D


signal applied(kind: String, player: Node)
signal expired(kind: String, player: Node)

@export var kind: String = "bubble"
@export var duration: float = 1.0

var _remaining: float = 0.0
var _active_player: Node = null


func apply_to(player: Node) -> void:
	if player == null:
		return
	_remaining = duration
	_active_player = player
	player.set_meta("active_powerup", kind)
	applied.emit(kind, player)


func tick(delta: float, player: Node) -> void:
	if not is_active():
		return
	_remaining -= maxf(delta, 0.0)
	if _remaining <= 0.0:
		_expire()


func is_active() -> bool:
	return _remaining > 0.0


func remaining() -> float:
	return maxf(_remaining, 0.0)


func reset() -> void:
	_expire()


func _expire() -> void:
	var previous_kind := kind
	var previous_player := _active_player
	_remaining = 0.0
	_active_player = null
	if previous_player != null and is_instance_valid(previous_player):
		previous_player.remove_meta("active_powerup")
	expired.emit(previous_kind, previous_player)
