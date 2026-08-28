class_name TreasureDashArena
extends Node2D

const PlayerInputScript := preload("res://player/player_input.gd")
const TreasureDashModeScript := preload("res://modes/treasure_dash_mode.gd")

const MATCH_DURATION: float = 180.0
const SPAWN_INTERVAL: float = 2.0
const MAX_ACTIVE_ITEMS: int = 24

@onready var rabbit = $Rabbit
@onready var fox = $Fox
@onready var rabbit_camera: Camera2D = $Rabbit/Camera2D
@onready var fox_camera: Camera2D = $Fox/Camera2D
@onready var touch_controls = $HUD/TouchControls
@onready var partner_indicator = $HUD/PartnerIndicator
@onready var collectibles_layer = $Collectibles

var local_role: String = "rabbit"
var dash_mode: RefCounted = null
var _spawn_timer: float = 0.0
var _remote_keys := {"left": false, "right": false, "jump": false, "action": false}
var _collectible_nodes: Dictionary = {}


func _ready() -> void:
	dash_mode = TreasureDashModeScript.new()
	dash_mode.start(MATCH_DURATION)
	dash_mode.configure_spawns(_collect_spawn_points(), MAX_ACTIVE_ITEMS)
	configure_local_role("rabbit")
	rabbit.set_meta("peer_id", 1)
	fox.set_meta("peer_id", 2)
	$FallRespawn.body_entered.connect(_respawn_fallen_hero)


func _physics_process(delta: float) -> void:
	dash_mode.tick(delta)
	_spawn_timer += delta
	if _spawn_timer >= SPAWN_INTERVAL and not dash_mode.is_finished():
		_spawn_timer = 0.0
		_try_spawn_collectible()
	_local_hero().apply_input(touch_controls.input_frame())
	apply_remote_desktop_frame(_desktop_remote_frame())


func _process(_delta: float) -> void:
	$SunnyForestBackground.set_focus_x(_local_hero().global_position.x)
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


func _collect_spawn_points() -> Array:
	var points: Array = []
	for marker in get_tree().get_nodes_in_group("td_spawn_point"):
		points.append(marker.global_position)
	return points


func _try_spawn_collectible() -> void:
	var collectible_id: String = dash_mode.try_spawn(_local_hero().global_position, _remote_hero().global_position)
	if collectible_id.is_empty():
		return
	var pos: Vector2 = dash_mode.spawn_position(collectible_id)
	var type: String = dash_mode.spawn_type(collectible_id)
	var node := Area2D.new()
	node.position = pos
	node.add_to_group("td_collectible")
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(24, 24)
	shape.shape = rect
	node.add_child(shape)
	var art := _make_collectible_art(type)
	node.add_child(art)
	node.body_entered.connect(_on_collectible_body_entered.bind(collectible_id, type))
	collectibles_layer.add_child(node)
	_collectible_nodes[collectible_id] = node


func _make_collectible_art(type: String) -> Polygon2D:
	var art := Polygon2D.new()
	art.polygon = _star_polygon()
	match type:
		"fruit":
			art.color = Color(0.9, 0.3, 0.25, 1)
		"gem":
			art.color = Color(0.3, 0.8, 0.95, 1)
		"star":
			art.color = Color(1, 0.87, 0.15, 1)
		_:
			art.color = Color(0.8, 0.8, 0.8, 1)
	return art


func _on_collectible_body_entered(body: Node, collectible_id: String, type: String) -> void:
	if not body.has_method("respawn"):
		return
	var peer_id: int = int(body.get_meta("peer_id", 0))
	if peer_id == 0:
		return
	if dash_mode.collect(peer_id, collectible_id, type):
		var node = _collectible_nodes.get(collectible_id)
		if node != null:
			node.queue_free()
			_collectible_nodes.erase(collectible_id)


func _star_polygon() -> PackedVector2Array:
	var points := PackedVector2Array()
	points.append(Vector2(0, -12))
	points.append(Vector2(5, -4))
	points.append(Vector2(12, -4))
	points.append(Vector2(6, 2))
	points.append(Vector2(8, 11))
	points.append(Vector2(0, 7))
	points.append(Vector2(-8, 11))
	points.append(Vector2(-6, 2))
	points.append(Vector2(-12, -4))
	points.append(Vector2(-5, -4))
	return points
