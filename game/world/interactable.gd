class_name Interactable
extends Area2D


signal activated(interactable_id: String, activator_peer_id: int)

@export var interactable_id: String = ""
@export var requires_host_authority: bool = true
@export var cooldown: float = 0.0
@export var heavy: bool = false

var _activated: bool = false
var _cooldown_remaining: float = 0.0


func _ready() -> void:
	if interactable_id.is_empty():
		interactable_id = name.to_snake_case()


func try_activate(activator_peer_id: int, host_peer_id: int = 1) -> bool:
	if requires_host_authority and activator_peer_id != host_peer_id:
		return false
	if _activated or _cooldown_remaining > 0.0:
		return false
	_activated = true
	_cooldown_remaining = cooldown
	activated.emit(interactable_id, activator_peer_id)
	return true


func validate_proximity(player: Node, max_distance: float) -> bool:
	if player == null or not (player is Node2D):
		return false
	return global_position.distance_to((player as Node2D).global_position) <= max_distance


func is_activated() -> bool:
	return _activated


func reset() -> void:
	_activated = false
	_cooldown_remaining = 0.0


func tick_cooldown(delta: float) -> void:
	if _cooldown_remaining > 0.0:
		_cooldown_remaining = maxf(_cooldown_remaining - maxf(delta, 0.0), 0.0)
