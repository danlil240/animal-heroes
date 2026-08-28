class_name Checkpoint
extends Area2D


signal activated(checkpoint_id: String, activator_peer_id: int)

@export var checkpoint_id: String = ""
@export var requires_host_authority: bool = true

var _confirmed: bool = false


func _ready() -> void:
	if checkpoint_id.is_empty():
		checkpoint_id = name.to_snake_case()
	monitoring = true
	if get_overlapping_bodies().is_empty():
		body_entered.connect(_on_body_entered)


func request_activate(activator_peer_id: int, host_peer_id: int = 1) -> bool:
	if requires_host_authority and activator_peer_id != host_peer_id:
		return false
	_confirmed = true
	activated.emit(checkpoint_id, activator_peer_id)
	return true


func is_confirmed() -> bool:
	return _confirmed


func reset() -> void:
	_confirmed = false


func _on_body_entered(body: Node) -> void:
	if not (body is CharacterBody2D):
		return
	var peer_id: int = int(body.get_meta("peer_id", 0))
	if peer_id == 0:
		return
	request_activate(peer_id, peer_id)
