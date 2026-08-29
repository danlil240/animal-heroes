class_name CameraFeedback
extends Camera2D

## A Camera2D variant used only by levels that opt into local movement feedback.

var _hero: CharacterBody2D = null
var _impulse: Vector2 = Vector2.ZERO
var _base_position: Vector2 = Vector2.ZERO
var _look_ahead_x: float = 0.0
var _base_position_captured: bool = false


func _ready() -> void:
	_capture_base_position()


func set_follow_hero(hero: CharacterBody2D) -> void:
	_capture_base_position()
	_hero = hero


func add_impulse(amount: float) -> void:
	_impulse += Vector2(0.0, amount)
	if _impulse.length() > 10.0:
		_impulse = _impulse.normalized() * 10.0


func _process(delta: float) -> void:
	advance_feedback(delta)


func advance_feedback(delta: float) -> void:
	if _hero == null or not is_instance_valid(_hero):
		return
	_capture_base_position()
	var step := maxf(delta, 0.0)
	var target_x := clampf(_hero.velocity.x * 0.22, -90.0, 90.0)
	_look_ahead_x = lerpf(_look_ahead_x, target_x, 1.0 - exp(-8.0 * step))
	_impulse = _impulse.lerp(Vector2.ZERO, 1.0 - exp(-18.0 * step))
	position = _base_position + Vector2(_look_ahead_x, 0.0) + _impulse


func _capture_base_position() -> void:
	if _base_position_captured:
		return
	_base_position = position
	_base_position_captured = true
