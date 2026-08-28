class_name StarRaceArena
extends Node2D

const PlayerInputScript := preload("res://player/player_input.gd")
const StarRaceModeScript := preload("res://modes/star_race_mode.gd")

@onready var rabbit = $Rabbit
@onready var fox = $Fox
@onready var rabbit_camera: Camera2D = $Rabbit/Camera2D
@onready var fox_camera: Camera2D = $Fox/Camera2D
@onready var touch_controls = $HUD/TouchControls
@onready var partner_indicator = $HUD/PartnerIndicator
@onready var finish_line = $FinishLine

var local_role: String = "rabbit"
var race_mode: RefCounted = null
var _host_tick: float = 0.0
var _remote_keys := {"left": false, "right": false, "jump": false, "action": false}
var _peer_checkpoints: Dictionary = {}


func _ready() -> void:
	race_mode = StarRaceModeScript.new()
	race_mode.start()
	configure_local_role("rabbit")
	rabbit.set_meta("peer_id", 1)
	fox.set_meta("peer_id", 2)
	_peer_checkpoints[1] = rabbit.global_position
	_peer_checkpoints[2] = fox.global_position
	$FallRespawn.body_entered.connect(_respawn_fallen_hero)
	finish_line.body_entered.connect(_on_finish_body_entered)
	for checkpoint in get_tree().get_nodes_in_group("race_checkpoint"):
		if checkpoint is Area2D:
			checkpoint.body_entered.connect(_on_checkpoint_body_entered.bind(checkpoint))


func _physics_process(delta: float) -> void:
	_host_tick += delta
	race_mode.tick(delta, _host_tick)
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


func _on_checkpoint_body_entered(body: Node, checkpoint: Area2D) -> void:
	if not body.has_method("respawn"):
		return
	var peer_id: int = int(body.get_meta("peer_id", 0))
	if peer_id == 0:
		return
	var checkpoint_id: String = checkpoint.get("checkpoint_id")
	if checkpoint_id.is_empty():
		return
	if race_mode.pass_checkpoint(peer_id, checkpoint_id, _host_tick):
		_peer_checkpoints[peer_id] = checkpoint.global_position


func _on_finish_body_entered(body: Node) -> void:
	if not body.has_method("respawn"):
		return
	var peer_id: int = int(body.get_meta("peer_id", 0))
	if peer_id == 0:
		return
	race_mode.finish(peer_id, _host_tick)


func _respawn_fallen_hero(body: Node2D) -> void:
	if not body.has_method("respawn"):
		return
	var peer_id: int = int(body.get_meta("peer_id", 0))
	var pos: Vector2 = _peer_checkpoints.get(peer_id, body.checkpoint_position)
	body.respawn(pos)
