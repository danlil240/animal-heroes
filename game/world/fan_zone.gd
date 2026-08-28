class_name FanZone
extends Area2D


@export var force_direction: Vector2 = Vector2.UP
@export var force_magnitude: float = 800.0
@export var active: bool = true

var _affected_bodies: Dictionary = {}


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func host_step(delta: float) -> void:
	if not active:
		return
	for body in _affected_bodies.values():
		if body == null or not is_instance_valid(body):
			continue
		if body is CharacterBody2D:
			body.velocity += force_direction.normalized() * force_magnitude * maxf(delta, 0.0)


func _on_body_entered(body: Node) -> void:
	if body is CharacterBody2D:
		_affected_bodies[body.get_instance_id()] = body


func _on_body_exited(body: Node) -> void:
	_affected_bodies.erase(body.get_instance_id())


func set_active(value: bool) -> void:
	active = value


func reset() -> void:
	_affected_bodies.clear()
	active = true
