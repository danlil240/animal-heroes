class_name SeedEnemyVisual
extends Node2D

var _elapsed: float = 0.0
var _state: String = "wait"
var _feedback_tween: Tween


func _process(delta: float) -> void:
	_elapsed += maxf(delta, 0.0)
	if _state == "wait":
		$Art.position.y = -42.0 + sin(_elapsed * 3.0) * 2.0
	elif _state == "telegraph":
		$Art.scale = Vector2(0.76, 0.55) + Vector2.ONE * sin(_elapsed * 20.0) * 0.025
	elif _state == "hop":
		$Art.rotation = sin(_elapsed * 10.0) * 0.08


func show_enemy_state(state: String, velocity: Vector2, direction: float) -> void:
	var entering_hurt := state == "hurt" and _state != "hurt"
	_state = state
	$Art.flip_h = direction < 0.0
	if state not in ["telegraph", "hurt"]:
		$Art.scale = Vector2(0.66, 0.66)
	if state == "hop":
		$Art.rotation = clampf(velocity.x / 900.0, -0.12, 0.12)
	elif state == "hurt":
		$Art.position.x = clampf(velocity.x * 0.025, -4.0, 4.0)
		if entering_hurt:
			_play_hurt_feedback()
	elif state == "defeated":
		var tween := create_tween().set_parallel(true)
		tween.tween_property($Art, "scale", Vector2(1.0, 0.1), 0.18)
		tween.tween_property($Art, "modulate:a", 0.0, 0.24)
	else:
		$Art.position.x = 0.0


func _play_hurt_feedback() -> void:
	if is_instance_valid(_feedback_tween):
		_feedback_tween.kill()
	$Art.scale = Vector2(0.84, 0.52)
	$Art.self_modulate = Color(1.45, 1.45, 1.45, 1.0)
	_feedback_tween = create_tween().set_parallel(true)
	_feedback_tween.tween_property($Art, "scale", Vector2(0.66, 0.66), 0.14)
	_feedback_tween.tween_property($Art, "self_modulate", Color.WHITE, 0.14)
