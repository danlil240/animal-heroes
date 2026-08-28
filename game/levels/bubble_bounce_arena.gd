class_name BubbleBounceArena
extends Node2D

const PlayerInputScript := preload("res://player/player_input.gd")
const BubbleBounceModeScript := preload("res://modes/bubble_bounce_mode.gd")

const MATCH_DURATION: float = 180.0
const BUBBLE_SPEED: float = 400.0
const BUBBLE_LIFETIME: float = 3.0
const BUBBLE_RADIUS: float = 16.0
const MAX_BUBBLES: int = 8
const REFILL_AMOUNT: int = 3
const MAX_AMMO: int = 5

@onready var rabbit = $Rabbit
@onready var fox = $Fox
@onready var rabbit_camera: Camera2D = $Rabbit/Camera2D
@onready var fox_camera: Camera2D = $Fox/Camera2D
@onready var touch_controls = $HUD/TouchControls
@onready var partner_indicator = $HUD/PartnerIndicator
@onready var projectiles_layer = $Projectiles

var local_role: String = "rabbit"
var bounce_mode: RefCounted = null
var _remote_keys := {"left": false, "right": false, "jump": false, "action": false}
var _bubbles: Array = []
var _bubble_id_counter: int = 0
var _ammo: Dictionary = {}
var _facing: Dictionary = {}


func _ready() -> void:
	bounce_mode = BubbleBounceModeScript.new()
	bounce_mode.start(MATCH_DURATION)
	configure_local_role("rabbit")
	rabbit.set_meta("peer_id", 1)
	fox.set_meta("peer_id", 2)
	_ammo[1] = REFILL_AMOUNT
	_ammo[2] = REFILL_AMOUNT
	_facing[1] = 1.0
	_facing[2] = -1.0
	for zone in get_tree().get_nodes_in_group("bubble_refill"):
		if zone is Area2D:
			zone.body_entered.connect(_on_refill_body_entered)


func _physics_process(delta: float) -> void:
	bounce_mode.tick(delta)
	_local_hero().apply_input(touch_controls.input_frame())
	apply_remote_desktop_frame(_desktop_remote_frame())
	_update_facing()
	_try_local_action()
	_update_bubbles(delta)


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


func _update_facing() -> void:
	for hero in [rabbit, fox]:
		var peer_id: int = int(hero.get_meta("peer_id", 0))
		if peer_id == 0:
			continue
		var vx: float = hero.velocity.x
		if vx > 1.0:
			_facing[peer_id] = 1.0
		elif vx < -1.0:
			_facing[peer_id] = -1.0


func _try_local_action() -> void:
	var hero = _local_hero()
	if hero.consume_action():
		var peer_id: int = int(hero.get_meta("peer_id", 0))
		_fire_bubble(peer_id, hero.global_position, _facing.get(peer_id, 1.0))
	var remote = _remote_hero()
	if remote.consume_action():
		var peer_id: int = int(remote.get_meta("peer_id", 0))
		_fire_bubble(peer_id, remote.global_position, _facing.get(peer_id, -1.0))


func _fire_bubble(owner_id: int, origin: Vector2, direction: float) -> void:
	if _bubbles.size() >= MAX_BUBBLES:
		return
	var ammo: int = int(_ammo.get(owner_id, 0))
	if ammo <= 0:
		return
	_ammo[owner_id] = ammo - 1
	_bubble_id_counter += 1
	var bubble_id := "bubble-%d" % _bubble_id_counter
	var bubble := Area2D.new()
	bubble.position = origin + Vector2(direction * 24, -8)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = BUBBLE_RADIUS
	shape.shape = circle
	bubble.add_child(shape)
	var art := Polygon2D.new()
	art.polygon = _bubble_polygon()
	art.color = Color(0.4, 0.8, 1, 0.7)
	bubble.add_child(art)
	projectiles_layer.add_child(bubble)
	_bubbles.append({
		"node": bubble,
		"owner_id": owner_id,
		"velocity": Vector2(direction * BUBBLE_SPEED, 0),
		"lifetime": BUBBLE_LIFETIME,
		"id": bubble_id,
		"origin": origin,
	})


func _update_bubbles(delta: float) -> void:
	var alive: Array = []
	for entry in _bubbles:
		var node: Area2D = entry["node"]
		if not is_instance_valid(node):
			continue
		entry["lifetime"] -= delta
		if entry["lifetime"] <= 0.0:
			node.queue_free()
			continue
		node.position += Vector2(entry["velocity"]) * delta
		var owner_id: int = entry["owner_id"]
		var bubble_id: String = entry["id"]
		var origin: Vector2 = entry["origin"]
		var hit_target := _check_bubble_hit(node, owner_id, bubble_id, origin)
		if hit_target:
			node.queue_free()
			continue
		alive.append(entry)
	_bubbles = alive


func _check_bubble_hit(bubble: Area2D, owner_id: int, bubble_id: String, origin: Vector2) -> bool:
	for hero in [rabbit, fox]:
		if not is_instance_valid(hero):
			continue
		var target_id: int = int(hero.get_meta("peer_id", 0))
		if target_id == 0 or target_id == owner_id:
			continue
		var dist: float = bubble.global_position.distance_to(hero.global_position)
		if dist <= BUBBLE_RADIUS + 24.0:
			var kb = bounce_mode.register_hit(owner_id, target_id, bubble_id, bounce_mode.time_remaining(), origin, hero.global_position)
			if kb != null and not kb.is_empty():
				hero.velocity = kb["velocity"]
			return true
	return false


func _on_refill_body_entered(body: Node) -> void:
	if not body.has_method("respawn"):
		return
	var peer_id: int = int(body.get_meta("peer_id", 0))
	if peer_id == 0:
		return
	_ammo[peer_id] = mini(int(_ammo.get(peer_id, 0)) + REFILL_AMOUNT, MAX_AMMO)


func _bubble_polygon() -> PackedVector2Array:
	var points := PackedVector2Array()
	var count: int = 12
	for i in count:
		var angle: float = TAU * float(i) / float(count)
		points.append(Vector2(cos(angle) * BUBBLE_RADIUS, sin(angle) * BUBBLE_RADIUS))
	return points
