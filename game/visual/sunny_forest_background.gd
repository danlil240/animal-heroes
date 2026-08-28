class_name SunnyForestBackground
extends Node2D

const FAR_RATIO: float = 0.08
const MID_RATIO: float = 0.18


func set_focus_x(world_x: float) -> void:
	$Far.position.x = -world_x * FAR_RATIO
	$Mid.position.x = -world_x * MID_RATIO
