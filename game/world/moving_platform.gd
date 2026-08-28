class_name MovingPlatform
extends AnimatableBody2D


@export var cycle_distance: float = 200.0
@export var cycle_speed: float = 60.0
@export var axis: String = "horizontal"
@export var host_phase: float = 0.0

var _origin: Vector2 = Vector2.ZERO
var _phase: float = 0.0


func _ready() -> void:
	_origin = global_position
	_phase = host_phase


func host_step(delta: float) -> void:
	_phase += cycle_speed * maxf(delta, 0.0) / cycle_distance if cycle_distance > 0.0 else 0.0
	var offset := sin(_phase * TAU) * cycle_distance
	if axis == "horizontal":
		global_position.x = _origin.x + offset
	else:
		global_position.y = _origin.y + offset


func snapshot() -> Dictionary:
	return {
		"phase": _phase,
		"position_x": global_position.x,
		"position_y": global_position.y,
	}


func restore(data: Dictionary) -> void:
	_phase = float(data.get("phase", _phase))
	global_position = Vector2(float(data.get("position_x", _origin.x)), float(data.get("position_y", _origin.y)))


func reset() -> void:
	_phase = host_phase
	global_position = _origin
