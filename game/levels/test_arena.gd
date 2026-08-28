class_name TestArena
extends TwoPlayerLevel

## Offline vertical-slice arena: one screen of safe ground, three platforms, ten
## stars, a fall-respawn zone, and a single checkpoint.


func _setup_level() -> void:
	$Checkpoint.body_entered.connect(_activate_checkpoint)


func _activate_checkpoint(body: Node2D) -> void:
	if not body.has_method("respawn"):
		return
	for hero in [rabbit, fox]:
		hero.checkpoint_position = $Checkpoint.global_position
	var visual := $Checkpoint.get_node_or_null("Visual")
	if visual != null and visual.has_method("set_active"):
		visual.set_active(true)
