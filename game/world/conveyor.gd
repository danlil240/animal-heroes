class_name Conveyor
extends StaticBody2D


@export var direction: float = 1.0
@export var speed: float = 120.0
@export var active: bool = true

var _velocity: Vector2 = Vector2.ZERO


func _ready() -> void:
	_update_velocity()


func host_step(_delta: float) -> void:
	if active:
		_update_velocity()
	else:
		_velocity = Vector2.ZERO
	constant_linear_velocity = _velocity


func _update_velocity() -> void:
	_velocity = Vector2(direction * speed, 0.0)


func set_active(value: bool) -> void:
	active = value
	_update_velocity()


func reset() -> void:
	active = true
	_update_velocity()
