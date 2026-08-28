class_name CheckpointVisual
extends Node2D

var _active: bool = false


func set_active(active: bool) -> void:
	if _active == active:
		return
	_active = active
	var target_scale := Vector2(1.08, 1.08) if active else Vector2.ONE
	var target_modulate := Color(1.18, 1.18, 1.05, 1.0) if active else Color.WHITE
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "scale", target_scale, 0.18)
	tween.tween_property(self, "modulate", target_modulate, 0.18)
