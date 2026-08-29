class_name BeetleEnemyVisual
extends Sprite2D

var _elapsed: float = 0.0
var _state: String = "patrol"


func _process(delta: float) -> void:
	_elapsed += maxf(delta, 0.0)
	if _state == "patrol":
		position.y = sin(_elapsed * 8.0) * 2.5
		rotation = sin(_elapsed * 8.0) * 0.035


func show_enemy_state(state: String, _velocity: Vector2, direction: float) -> void:
	_state = state
	flip_h = direction < 0.0
	if state == "defeated":
		var tween := create_tween().set_parallel(true)
		tween.tween_property(self, "scale:y", 0.12, 0.18)
		tween.tween_property(self, "modulate:a", 0.0, 0.24)
