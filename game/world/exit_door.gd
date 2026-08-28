class_name ExitDoor
extends Area2D


signal all_players_present()

@export var required_players: int = 2

var _present_players: Dictionary = {}


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node) -> void:
	if not _is_player(body):
		return
	_present_players[body.get_instance_id()] = true
	if _present_players.size() >= required_players:
		all_players_present.emit()


func _on_body_exited(body: Node) -> void:
	if not _is_player(body):
		return
	_present_players.erase(body.get_instance_id())


func _is_player(body: Node) -> bool:
	return body is CharacterBody2D and body.has_method("respawn")


func reset() -> void:
	_present_players.clear()
