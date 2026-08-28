class_name RaceCheckpoint
extends Area2D


@export var checkpoint_id: String = ""


func _ready() -> void:
	if checkpoint_id.is_empty():
		checkpoint_id = name.to_snake_case()
