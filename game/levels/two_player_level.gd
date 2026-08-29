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

const NET_SYNC_HZ: float = 20.0
const _NET_SYNC_INTERVAL: float = 1.0 / NET_SYNC_HZ
const SPRING_CAMERA_IMPULSE: float = 5.0

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
var _net_sync_accumulator: float = 0.0
var _remote_input_frame = null
var _has_remote_input: bool = false
var _last_world_request_by_peer: Dictionary = {}
var _next_local_world_request_sequence: int = 0
var _next_world_event_sequence: int = 0
var _last_applied_world_event_sequence: int = 0


func _ready() -> void:
	_background = _find_background()
	configure_local_role(local_role)
	_connect_spring_feedback()
	var fall_zone := get_node_or_null("FallRespawn")
	if fall_zone != null:
		fall_zone.body_entered.connect(_respawn_fallen_hero)
	if touch_controls.has_signal("pause_requested"):
		touch_controls.pause_requested.connect(_on_pause_requested)
	_setup_level()


func _physics_process(delta: float) -> void:
	for spring in get_tree().get_nodes_in_group("spring_pad"):
		if spring.has_method("host_step"):
			spring.host_step(delta)
	_step_level(delta)
	route_control_frames()
	apply_remote_desktop_frame(_desktop_remote_frame())
	_net_sync_accumulator += delta
	if _net_sync_accumulator >= _NET_SYNC_INTERVAL:
		_net_sync_accumulator = 0.0
		_sync_over_network()


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
	_configure_local_camera_feedback()
	# The local hero always simulates. The partner keeps simulating too until
	# network state actually arrives, so offline play, the local arena, and the
	# desktop keyboard second player all still move under their own physics.
	_local_hero().is_network_remote = false
	_remote_hero().is_network_remote = _has_remote_input
	partner_indicator.update_for_world_positions(_local_hero().global_position, _remote_hero().global_position)


## Delivers this device's touch controls to the local hero only.
func route_control_frames() -> void:
	_local_hero().apply_input(touch_controls.input_frame())


func apply_remote_desktop_frame(frame) -> void:
	if not _has_remote_input:
		_remote_hero().apply_input(frame)


## Sends the local hero's input frame and position to the other tablet via RPC.
func _sync_over_network() -> void:
	var session = get_node_or_null("/root/Session")
	if session == null or session.state != Session.PLAYING:
		return
	if session._peer == null:
		return
	var frame: PlayerInputScript.InputFrame = touch_controls.input_frame()
	var pos: Vector2 = _local_hero().global_position
	var vel: Vector2 = _local_hero().velocity
	_receive_remote_state.rpc(frame.axis, frame.jump, frame.action, pos, vel)


@rpc("any_peer", "unreliable_ordered")
func _receive_remote_state(axis: float, jump: bool, action: bool, pos: Vector2, vel: Vector2) -> void:
	var remote: CharacterBody2D = _remote_hero()
	# The partner is owned by the other tablet from this point on. Hand it over
	# to network state so local gravity stops fighting the incoming position.
	_has_remote_input = true
	remote.is_network_remote = true
	# Apply the owner's authoritative state directly instead of local physics.
	if remote.has_method("apply_network_state"):
		remote.apply_network_state(pos, vel, axis, jump, action)
	else:
		# Fallback for non-PlayerBody heroes
		remote.global_position = pos
		remote.velocity = vel


## Announces the end of the level or match exactly once.
func finish_level(result: Dictionary) -> void:
	if _finished:
		return
	_finished = true
	level_finished.emit(result)


func is_finished() -> bool:
	return _finished


## Sends one rising-edge context action to the host. Offline scenes process the
## same request locally through process_world_action().
func request_world_action(action_id: String, target_id: String, hero_position: Vector2) -> void:
	if action_id.is_empty() or target_id.is_empty():
		return
	_next_local_world_request_sequence += 1
	if _is_world_authority():
		var peer_id := int(_local_hero().get("peer_id"))
		process_world_action(peer_id, _next_local_world_request_sequence, action_id, target_id, hero_position)
	else:
		_receive_world_action.rpc_id(1, _next_local_world_request_sequence, action_id, target_id, hero_position)


## Production request-processing boundary shared by local-host input and RPC.
## The RPC obtains peer_id from MultiplayerAPI and never accepts it from payload.
func process_world_action(peer_id: int, request_sequence: int, action_id: String, target_id: String, hero_position: Vector2) -> bool:
	if peer_id <= 0 or request_sequence <= 0 or action_id.is_empty() or target_id.is_empty():
		return false
	var last_sequence := int(_last_world_request_by_peer.get(peer_id, 0))
	if request_sequence <= last_sequence:
		return false
	_last_world_request_by_peer[peer_id] = request_sequence
	var event: Dictionary = _validate_world_action(peer_id, action_id, target_id, hero_position)
	var kind := String(event.get("kind", ""))
	var payload: Variant = event.get("payload", null)
	if kind.is_empty() or not payload is Dictionary:
		return false
	_next_world_event_sequence += 1
	if not apply_world_event(_next_world_event_sequence, kind, payload):
		return false
	if _has_live_world_peer() and _is_world_authority():
		_receive_world_event.rpc(_next_world_event_sequence, kind, payload)
	return true


func apply_world_event(event_sequence: int, kind: String, payload: Dictionary) -> bool:
	if event_sequence <= _last_applied_world_event_sequence or kind.is_empty():
		return false
	_last_applied_world_event_sequence = event_sequence
	_apply_world_event(event_sequence, kind, payload)
	return true


func last_world_event_sequence() -> int:
	return _last_applied_world_event_sequence


@rpc("any_peer", "reliable")
func _receive_world_action(request_sequence: int, action_id: String, target_id: String, hero_position: Vector2) -> void:
	if not _is_world_authority():
		return
	process_world_action(multiplayer.get_remote_sender_id(), request_sequence, action_id, target_id, hero_position)


@rpc("authority", "reliable")
func _receive_world_event(event_sequence: int, kind: String, payload: Dictionary) -> void:
	apply_world_event(event_sequence, kind, payload)


func _is_world_authority() -> bool:
	var session = get_node_or_null("/root/Session")
	return session == null or session.state != Session.PLAYING or session.is_host()


func _has_live_world_peer() -> bool:
	var session = get_node_or_null("/root/Session")
	return session != null and session.state == Session.PLAYING and session._peer != null


# Hooks for concrete levels.

func _setup_level() -> void:
	pass


func _step_level(_delta: float) -> void:
	pass


func _present_level(_delta: float) -> void:
	pass


func _validate_world_action(_peer_id: int, _action_id: String, _target_id: String, _hero_position: Vector2) -> Dictionary:
	return {}


func _apply_world_event(_sequence: int, _kind: String, _payload: Dictionary) -> void:
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


func _local_camera() -> Camera2D:
	return rabbit_camera if local_role == RABBIT_ROLE else fox_camera


func _configure_local_camera_feedback() -> void:
	var camera := _local_camera()
	if camera.enabled and camera.has_method("set_follow_hero"):
		camera.call("set_follow_hero", _local_hero())


func _connect_spring_feedback() -> void:
	for spring in get_tree().get_nodes_in_group("spring_pad"):
		if spring.has_signal("launched") and not spring.is_connected("launched", _on_spring_launched):
			spring.connect("launched", _on_spring_launched)


func _on_spring_launched(peer_id: int) -> void:
	if peer_id != int(_local_hero().get("peer_id")):
		return
	var camera := _local_camera()
	if camera.enabled and camera.has_method("add_impulse"):
		camera.call("add_impulse", SPRING_CAMERA_IMPULSE)


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
