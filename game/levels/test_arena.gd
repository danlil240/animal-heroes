class_name TestArena
extends Node2D

const PlayerInputScript := preload("res://player/player_input.gd")

@onready var rabbit = $Rabbit
@onready var fox = $Fox
@onready var rabbit_camera: Camera2D = $Rabbit/Camera2D
@onready var fox_camera: Camera2D = $Fox/Camera2D
@onready var touch_controls = $HUD/TouchControls
@onready var partner_indicator = $HUD/PartnerIndicator

var local_role: String = "rabbit"
var _remote_keys := {"left": false, "right": false, "jump": false, "action": false}


func _ready() -> void:
	configure_local_role("rabbit")
	$FallRespawn.body_entered.connect(_respawn_fallen_hero)
	$Checkpoint.body_entered.connect(_activate_checkpoint)


func _physics_process(_delta: float) -> void:
	route_control_frames()
	apply_remote_desktop_frame(_desktop_remote_frame())


func _process(_delta: float) -> void:
	partner_indicator.update_for_world_positions(_local_hero().global_position, _remote_hero().global_position)


func configure_local_role(role: String) -> void:
	if role != "rabbit" and role != "fox":
		push_error("local role must be rabbit or fox")
		return
	local_role = role
	var rabbit_is_local := role == "rabbit"
	rabbit_camera.enabled = rabbit_is_local
	fox_camera.enabled = not rabbit_is_local
	if rabbit_is_local:
		rabbit_camera.make_current()
	else:
		fox_camera.make_current()
	partner_indicator.update_for_world_positions(_local_hero().global_position, _remote_hero().global_position)


func route_control_frames() -> void:
	_local_hero().apply_input(touch_controls.input_frame())


func apply_remote_desktop_frame(frame) -> void:
	_remote_hero().apply_input(frame)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and not event.echo:
		var key_event := event as InputEventKey
		match key_event.keycode:
			KEY_J:
				_remote_keys.left = key_event.pressed
			KEY_L:
				_remote_keys.right = key_event.pressed
			KEY_I:
				_remote_keys.jump = key_event.pressed
			KEY_O:
				_remote_keys.action = key_event.pressed


func _desktop_remote_frame():
	var frame := PlayerInputScript.InputFrame.new()
	frame.axis = float(int(_remote_keys.right) - int(_remote_keys.left))
	frame.jump = _remote_keys.jump
	frame.action = _remote_keys.action
	return frame


func _local_hero():
	return rabbit if local_role == "rabbit" else fox


func _remote_hero():
	return fox if local_role == "rabbit" else rabbit


func _respawn_fallen_hero(body: Node2D) -> void:
	if body.has_method("respawn"):
		body.respawn(body.checkpoint_position)


func _activate_checkpoint(body: Node2D) -> void:
	if not body.has_method("respawn"):
		return
	for hero in [rabbit, fox]:
		hero.checkpoint_position = $Checkpoint.global_position
	var visual := $Checkpoint.get_node_or_null("Visual")
	if visual != null and visual.has_method("set_active"):
		visual.set_active(true)
