class_name CrystalCaves
extends CoopLevel

## Cooperative level 2: host-stepped moving platforms, paired switches and
## doors, and the fox's heavy push.

var _moving_platforms: Array = []
var _doors: Dictionary = {}


func _setup_coop_level() -> void:
	_moving_platforms = get_tree().get_nodes_in_group("moving_platform")
	for node in get_tree().get_nodes_in_group("switch_door_pair"):
		if node is StaticBody2D and node.has_method("switch_activated"):
			_doors[node.door_id] = node
		elif node is Area2D and node.has_signal("activated"):
			node.activated.connect(_on_switch_activated)


func _step_level(delta: float) -> void:
	for platform in _moving_platforms:
		if platform.has_method("host_step"):
			platform.host_step(delta)


func _on_switch_activated(interactable_id: String, _peer_id: int) -> void:
	for door in _doors.values():
		door.switch_activated(interactable_id)
