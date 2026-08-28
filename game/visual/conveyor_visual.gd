class_name ConveyorVisual
extends Node2D

var _elapsed: float = 0.0

func _process(delta: float) -> void:
	_elapsed += maxf(delta, 0.0)
	$Belt.position.x = fmod(_elapsed * 40.0, 40.0) - 20.0
