class_name CloudFactory
extends Node2D

const PlayerInputScript := preload("res://player/player_input.gd")
const CoopMode = preload("res://modes/coop_mode.gd")

@export var enemy_budget: int = 10
@export var projectile_budget: int = 20
@export var particle_budget: int = 64

@onready var rabbit = $Rabbit
@onready var fox = $Fox
@onready var rabbit_camera: Camera2D = $Rabbit/Camera2D
@onready var fox_camera: Camera2D = $Fox/Camera2D
@onready var touch_controls = $HUD/TouchControls
@onready var partner_indicator = $HUD/PartnerIndicator
@onready var boss_entrance = $BossEntrance

var local_role: String = "rabbit"
var coop_mode: RefCounted = null
var _remote_keys := {"left": false, "right": false, "jump": false, "action": false}
var _fans: Array = []
var _conveyors: Array = []


func _ready() -> void:
	coop_mode = CoopMode.new()
	coop_mode.start("cloud_factory", ["sunny_forest", "crystal_caves", "cloud_factory"])
	configure_local_role("rabbit")
	$FallRespawn.body_entered.connect(_respawn_fallen_hero)
	_fans = get_tree().get_nodes_in_group("fan_zone")
	_conveyors = get_tree().get_nodes_in_group("conveyor")
	for checkpoint in get_tree().get_nodes_in_group("checkpoint"):
		if checkpoint.has_signal("activated"):
			checkpoint.activated.connect(_on_checkpoint_activated)


func _physics_process(delta: float) -> void:
	for fan in _fans:
		if fan.has_method("host_step"):
			fan.host_step(delta)
	for conveyor in _conveyors:
		if conveyor.has_method("host_step"):
			conveyor.host_step(delta)
	_local_hero().apply_input(touch_controls.input_frame())
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


func _on_checkpoint_activated(checkpoint_id: String, _peer_id: int) -> void:
	coop_mode.confirm_checkpoint(checkpoint_id)
	for hero in [rabbit, fox]:
		hero.checkpoint_position = _checkpoint_position(checkpoint_id)


func _checkpoint_position(checkpoint_id: String) -> Vector2:
	for checkpoint in get_tree().get_nodes_in_group("checkpoint"):
		if checkpoint.get("checkpoint_id") == checkpoint_id:
			return checkpoint.global_position
	return rabbit.checkpoint_position
