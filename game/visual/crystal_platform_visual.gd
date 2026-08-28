class_name CrystalPlatformVisual
extends Node2D

@export var ground_variant: bool = false

func _ready() -> void:
	$Ground.visible = ground_variant
	$Small.visible = not ground_variant
