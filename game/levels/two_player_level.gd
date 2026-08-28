class_name TwoPlayerLevel
extends Node2D

## Shared scaffolding for every two-player level and arena.
##
## Concrete levels override the `_setup_level`, `_step_level`, and
## `_present_level` hooks instead of `_ready`, `_physics_process`, and
## `_process`, so hero references, role assignment, camera ownership, input
## routing, fall respawn, parallax focus, and partner presentation stay defined
## in one place.

## Reported once when the level or match reaches its end state.
signal level_finished(result: Dictionary)
## Reported when a player asks to leave the level from the in-game controls.
signal exit_requested()

const PlayerInputScript := preload("res://player/player_input.gd")

const RABBIT_ROLE := "rabbit"
const FOX_ROLE := "fox"

## Second-player keyboard mapping for desktop testing; tablets use touch.
const REMOTE_KEY_ACTIONS := {
	KEY_J: "left",
	KEY_L: "right",
	KEY_I: "jump",
	KEY_O: "action",
}

@onready var rabbit = $Rabbit
@onready var fox = $Fox
@onready var rabbit_camera: Camera2D = $Rabbit/Camera2D
@onready var fox_camera: Camera2D = $Fox/Camera2D
@onready var touch_controls = $HUD/TouchControls
@onready var partner_indicator = $HUD/PartnerIndicator

var local_role: String = RABBIT_ROLE

var _background: Node2D = null
var _remote_keys := {"left": false, "right": false, "jump": false, "action": false}
var _finished: bool = false


func _ready() -> void:
	_background = _find_background()
	configure_local_role(local_role)
	var fall_zone := get_node_or_null("FallRespawn")
	if fall_zone != null:
		fall_zone.body_entered.connect(_respawn_fallen_hero)
	if touch_controls.has_signal("pause_requested"):
		touch_controls.pause_requested.connect(_on_pause_requested)
	_setup_level()


func _physics_process(delta: float) -> void:
	_step_level(delta)
	route_control_frames()
	apply_remote_desktop_frame(_desktop_remote_frame())


func _process(delta: float) -> void:
	var local_position: Vector2 = _local_hero().global_position
	if _background != null:
		_background.set_focus_x(local_position.x)
	partner_indicator.update_for_world_positions(local_position, _remote_hero().global_position)
	_present_level(delta)


## Assigns which hero this device drives; the other hero follows remote input.
func configure_local_role(role: String) -> void:
	if role != RABBIT_ROLE and role != FOX_ROLE:
		push_error("local role must be rabbit or fox")
		return
	local_role = role
	var rabbit_is_local := role == RABBIT_ROLE
	rabbit_camera.enabled = rabbit_is_local
	fox_camera.enabled = not rabbit_is_local
	if rabbit_is_local:
		rabbit_camera.make_current()
	else:
		fox_camera.make_current()
	partner_indicator.update_for_world_positions(_local_hero().global_position, _remote_hero().global_position)


## Delivers this device's touch controls to the local hero only.
func route_control_frames() -> void:
	_local_hero().apply_input(touch_controls.input_frame())


func apply_remote_desktop_frame(frame) -> void:
	_remote_hero().apply_input(frame)


## Announces the end of the level or match exactly once.
func finish_level(result: Dictionary) -> void:
	if _finished:
		return
	_finished = true
	level_finished.emit(result)


func is_finished() -> bool:
	return _finished


# Hooks for concrete levels.

func _setup_level() -> void:
	pass


func _step_level(_delta: float) -> void:
	pass


func _present_level(_delta: float) -> void:
	pass


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or event.echo:
		return
	var key_event := event as InputEventKey
	if not REMOTE_KEY_ACTIONS.has(key_event.keycode):
		return
	_remote_keys[REMOTE_KEY_ACTIONS[key_event.keycode]] = key_event.pressed


func _desktop_remote_frame():
	var frame := PlayerInputScript.InputFrame.new()
	frame.axis = float(int(_remote_keys.right) - int(_remote_keys.left))
	frame.jump = _remote_keys.jump
	frame.action = _remote_keys.action
	return frame


func _local_hero():
	return rabbit if local_role == RABBIT_ROLE else fox


func _remote_hero():
	return fox if local_role == RABBIT_ROLE else rabbit


func _respawn_fallen_hero(body: Node2D) -> void:
	if body.has_method("respawn"):
		body.respawn(body.checkpoint_position)


## The level's parallax backdrop, whatever world it belongs to.
func _find_background() -> Node2D:
	for child in get_children():
		if child is Node2D and child.has_method("set_focus_x"):
			return child
	return null


func _on_pause_requested() -> void:
	exit_requested.emit()
