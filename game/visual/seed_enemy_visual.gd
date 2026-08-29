class_name SeedEnemyVisual
extends Node2D

var _elapsed: float = 0.0
var _state: String = "wait"


func _process(delta: float) -> void:
	_elapsed += maxf(delta, 0.0)
	if _state == "wait":
		$Art.position.y = -42.0 + sin(_elapsed * 3.0) * 2.0
	elif _state == "telegraph":
		$Art.scale = Vector2(0.76, 0.55) + Vector2.ONE * sin(_elapsed * 20.0) * 0.025
	elif _state == "hop":
		$Art.rotation = sin(_elapsed * 10.0) * 0.08


func show_enemy_state(state: String, velocity: Vector2, direction: float) -> void:
	_state = state
	$Art.flip_h = direction < 0.0
	if state != "telegraph":
		$Art.scale = Vector2(0.66, 0.66)
	if state == "hop":
		$Art.rotation = clampf(velocity.x / 900.0, -0.12, 0.12)
	elif state == "defeated":
		var tween := create_tween().set_parallel(true)
		tween.tween_property($Art, "scale", Vector2(1.0, 0.1), 0.18)
		tween.tween_property($Art, "modulate:a", 0.0, 0.24)
