class_name FanVisual
extends Node2D

var _elapsed: float = 0.0

func _process(delta: float) -> void:
	_elapsed += maxf(delta, 0.0)
	$Blades.rotation = _elapsed * 6.0
