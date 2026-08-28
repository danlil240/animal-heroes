class_name HeroVisual
extends Node2D

@export_enum("rabbit", "fox") var kind: String = "rabbit"

var _body: CharacterBody2D
var _elapsed: float = 0.0
var _last_action_pressed: bool = false
var _last_hearts: int = -1
var _last_body_position: Vector2
var _effect_tween: Tween


func _ready() -> void:
	configure(kind, get_parent() as CharacterBody2D)


func configure(hero_kind: String, body: CharacterBody2D) -> void:
	kind = hero_kind
	_body = body
	$Pose/RabbitArt.visible = kind == "rabbit"
	$Pose/FoxArt.visible = kind == "fox"
	$Pose/ActionBubble.visible = false
	if _body != null:
		_last_body_position = _body.global_position
		if _body.has_method("snapshot"):
			_last_hearts = _body.snapshot().hearts


func _process(delta: float) -> void:
	if _body == null:
		return
	var step := maxf(delta, 0.0)
	_elapsed += step
	var grounded := _body.is_on_floor()
	var speed := absf(_body.velocity.x)
	var target_position := Vector2(0.0, -30.0)
	var target_rotation := 0.0
	var target_stretch := Vector2.ONE
	if grounded and speed < 1.0:
		target_position.y += sin(_elapsed * 3.2) * 2.0
	elif grounded:
		target_position.y += sin(_elapsed * 12.0) * 5.0
		target_rotation = sin(_elapsed * 12.0) * 0.05
	elif _body.velocity.y < 0.0:
		target_stretch = Vector2(0.94, 1.08)
	else:
		target_stretch = Vector2(1.05, 0.95)
	var direction: float = _body.facing_direction if "facing_direction" in _body else 1.0
	target_stretch.x *= direction
	var smoothing := 1.0 - exp(-12.0 * step)
	$Pose.position = $Pose.position.lerp(target_position, smoothing)
	$Pose.rotation = lerpf($Pose.rotation, target_rotation, smoothing)
	$Pose.scale = $Pose.scale.lerp(target_stretch, smoothing)
	_update_state_effects()


func _update_state_effects() -> void:
	if not _body.has_method("snapshot"):
		return
	var state = _body.snapshot()
	if state.action_pressed and not _last_action_pressed:
		_play_action_effect()
	if _last_hearts >= 0 and state.hearts < _last_hearts:
		_play_recoil()
	elif _last_hearts >= 0 and state.hearts > _last_hearts and _body.global_position.distance_to(_last_body_position) > 40.0:
		_play_recovery()
	_last_action_pressed = state.action_pressed
	_last_hearts = state.hearts
	_last_body_position = _body.global_position


func _play_action_effect() -> void:
	$Pose/ActionBubble.visible = true
	$Pose/ActionBubble.scale = Vector2(0.25, 0.25)
	$Pose/ActionBubble.modulate.a = 1.0
	var tween := create_tween().set_parallel(true)
	tween.tween_property($Pose/ActionBubble, "scale", Vector2.ONE, 0.16)
	tween.tween_property($Pose/ActionBubble, "modulate:a", 0.0, 0.16)
	tween.chain().tween_callback($Pose/ActionBubble.hide)


func _play_recoil() -> void:
	if _effect_tween != null:
		_effect_tween.kill()
	_effect_tween = create_tween()
	_effect_tween.tween_property($Pose, "modulate", Color(1.0, 0.55, 0.55, 1.0), 0.08)
	_effect_tween.tween_property($Pose, "modulate", Color.WHITE, 0.10)


func _play_recovery() -> void:
	if _effect_tween != null:
		_effect_tween.kill()
	_effect_tween = create_tween()
	_effect_tween.tween_property($Pose, "modulate", Color(1.2, 1.2, 0.85, 1.0), 0.10)
	_effect_tween.tween_property($Pose, "modulate", Color.WHITE, 0.12)
