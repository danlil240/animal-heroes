class_name SunnyForest
extends CoopLevel

## Cooperative level 1: teaches movement, stomping, the bubble power-up, and the
## partner switch that opens the shared exit.

@onready var exit_node = $Exit

var _players_at_exit: Dictionary = {}


func _setup_coop_level() -> void:
	exit_node.body_entered.connect(_on_exit_body_entered)
	exit_node.body_exited.connect(_on_exit_body_exited)


func _on_exit_body_entered(body: Node2D) -> void:
	if not body.has_method("respawn"):
		return
	_players_at_exit[body.get_instance_id()] = true
	if _players_at_exit.size() >= exit_node.required_players:
		coop_mode.complete_level()


func _on_exit_body_exited(body: Node2D) -> void:
	if not body.has_method("respawn"):
		return
	_players_at_exit.erase(body.get_instance_id())
