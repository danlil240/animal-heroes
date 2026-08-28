class_name CoopLevel
extends TwoPlayerLevel

## Shared scaffolding for the cooperative campaign levels: the CoopMode rules
## object, confirmed checkpoints shared by both heroes, and the completion
## payload the app shell needs in order to unlock and open the next level.

const CoopModeScript := preload("res://modes/coop_mode.gd")

## Campaign identifier for this level; set on the scene root.
@export var level_id: String = ""

var coop_mode: RefCounted = null


func _setup_level() -> void:
	if level_id.is_empty():
		push_error("cooperative level must declare level_id")
	coop_mode = CoopModeScript.new()
	coop_mode.start(level_id, levels_unlocked_through(level_id))
	coop_mode.level_completed.connect(_on_coop_level_completed)
	coop_mode.campaign_completed.connect(_on_coop_campaign_completed)
	for checkpoint in get_tree().get_nodes_in_group("checkpoint"):
		if checkpoint.has_signal("activated"):
			checkpoint.activated.connect(_on_checkpoint_activated)
	_setup_coop_level()


func _setup_coop_level() -> void:
	pass


## Campaign levels up to and including `id`, in campaign order.
static func levels_unlocked_through(id: String) -> Array:
	var levels: Array = []
	for level in CoopModeScript.CAMPAIGN_LEVELS:
		levels.append(level)
		if level == id:
			break
	return levels


static func next_campaign_level(id: String) -> String:
	var index: int = CoopModeScript.CAMPAIGN_LEVELS.find(id)
	if index < 0 or index + 1 >= CoopModeScript.CAMPAIGN_LEVELS.size():
		return ""
	return CoopModeScript.CAMPAIGN_LEVELS[index + 1]


func _on_checkpoint_activated(checkpoint_id: String, _peer_id: int) -> void:
	coop_mode.confirm_checkpoint(checkpoint_id)
	var checkpoint_position := _checkpoint_position(checkpoint_id)
	for hero in [rabbit, fox]:
		hero.checkpoint_position = checkpoint_position


func _checkpoint_position(checkpoint_id: String) -> Vector2:
	for checkpoint in get_tree().get_nodes_in_group("checkpoint"):
		if checkpoint.get("checkpoint_id") == checkpoint_id:
			return checkpoint.global_position
	return rabbit.checkpoint_position


func _on_coop_level_completed(completed_level_id: String) -> void:
	finish_level({
		"mode": "coop",
		"level_id": completed_level_id,
		"next_level_id": next_campaign_level(completed_level_id),
		"unlocked_levels": coop_mode.unlocked_levels.duplicate(),
		"campaign_completed": coop_mode.is_campaign_completed(),
		"winner_peer_id": 0,
		"scores": {},
	})


func _on_coop_campaign_completed(unlocked_levels: Array) -> void:
	finish_level({
		"mode": "coop",
		"level_id": level_id,
		"next_level_id": "",
		"unlocked_levels": unlocked_levels.duplicate(),
		"campaign_completed": true,
		"winner_peer_id": 0,
		"scores": {},
	})
