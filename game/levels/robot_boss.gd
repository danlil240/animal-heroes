class_name RobotBossArena
extends Node2D

const PlayerInputScript := preload("res://player/player_input.gd")
const CoopMode = preload("res://modes/coop_mode.gd")
const RobotBoss = preload("res://world/robot_boss.gd")

@onready var rabbit = $Rabbit
@onready var fox = $Fox
@onready var rabbit_camera: Camera2D = $Rabbit/Camera2D
@onready var fox_camera: Camera2D = $Fox/Camera2D
@onready var touch_controls = $HUD/TouchControls
@onready var partner_indicator = $HUD/PartnerIndicator

var local_role: String = "rabbit"
var coop_mode: RefCounted = null
var boss: RobotBoss = null
var _remote_keys := {"left": false, "right": false, "jump": false, "action": false}


func _ready() -> void:
	coop_mode = CoopMode.new()
	coop_mode.start("robot_boss", ["sunny_forest", "crystal_caves", "cloud_factory", "robot_boss"])
	boss = RobotBoss.new()
	boss.begin(true)
	boss.defeated.connect(_on_boss_defeated)
	configure_local_role("rabbit")
	$FallRespawn.body_entered.connect(_respawn_fallen_hero)


func _physics_process(delta: float) -> void:
	boss.host_step(delta)
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


func activate_switch(switch_id: int) -> void:
	boss.activate_switch(switch_id)


func hit_weak_point(weak_point_id: int) -> void:
	boss.hit_weak_point(weak_point_id)


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


func _on_boss_defeated() -> void:
	coop_mode.complete_campaign()
