class_name CollectibleVisual
extends Node2D

signal finished

@export var phase_offset: float = 0.0

var _elapsed: float = 0.0
var _collected: bool = false


func _process(delta: float) -> void:
	if _collected:
		return
	_elapsed += maxf(delta, 0.0)
	var phase := _elapsed * 2.5 + phase_offset
	$Art.position.y = sin(phase) * 5.0
	$Art.rotation = sin(phase * 0.7) * 0.06


func set_phase_offset(value: float) -> void:
	phase_offset = value


func play_collected() -> void:
	if _collected:
		return
	_collected = true
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "scale", Vector2(1.35, 1.35), 0.16)
	tween.tween_property(self, "modulate:a", 0.0, 0.16)
	tween.chain().tween_callback(finished.emit)
