class_name BeetleEnemyVisual
extends Sprite2D

var _elapsed: float = 0.0
var _state: String = "patrol"
var _feedback_tween: Tween
var _base_scale: Vector2 = Vector2.ONE


func _ready() -> void:
	_base_scale = scale


func _process(delta: float) -> void:
	_elapsed += maxf(delta, 0.0)
	if _state == "patrol":
		position.y = sin(_elapsed * 8.0) * 2.5
		rotation = sin(_elapsed * 8.0) * 0.035


func show_enemy_state(state: String, velocity: Vector2, direction: float) -> void:
	var entering_hurt := state == "hurt" and _state != "hurt"
	_state = state
	flip_h = direction < 0.0
	if state == "hurt":
		position.x = clampf(velocity.x * 0.025, -4.0, 4.0)
		if entering_hurt:
			_play_hurt_feedback()
	elif state == "defeated":
		var tween := create_tween().set_parallel(true)
		tween.tween_property(self, "scale:y", 0.12, 0.18)
		tween.tween_property(self, "modulate:a", 0.0, 0.24)
	else:
		position.x = 0.0


func _play_hurt_feedback() -> void:
	if is_instance_valid(_feedback_tween):
		_feedback_tween.kill()
	scale = Vector2(_base_scale.x * 1.18, _base_scale.y * 0.8)
	self_modulate = Color(1.45, 1.45, 1.45, 1.0)
	_feedback_tween = create_tween().set_parallel(true)
	_feedback_tween.tween_property(self, "scale", _base_scale, 0.14)
	_feedback_tween.tween_property(self, "self_modulate", Color.WHITE, 0.14)
