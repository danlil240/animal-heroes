class_name BubbleBounceArena
extends CompetitionArena

## Friendly bubble match: no elimination pits, bounded knockback, refill zones,
## and one point per valid hit.

const BubbleBounceModeScript := preload("res://modes/bubble_bounce_mode.gd")

const MATCH_DURATION: float = 180.0
const BUBBLE_SPEED: float = 400.0
const BUBBLE_LIFETIME: float = 3.0
const BUBBLE_RADIUS: float = 16.0
const HIT_RADIUS: float = 24.0
const MAX_BUBBLES: int = 8
const REFILL_AMOUNT: int = 3
const MAX_AMMO: int = 5

@onready var projectiles_layer = $Projectiles

var bounce_mode: RefCounted = null

var _bubbles: Array = []
var _bubble_id_counter: int = 0
var _ammo: Dictionary = {}
var _facing: Dictionary = {}


func _setup_arena() -> void:
	bounce_mode = BubbleBounceModeScript.new()
	bounce_mode.start(MATCH_DURATION)
	bounce_mode.match_completed.connect(_finish_match)
	_ammo[HOST_PEER_ID] = REFILL_AMOUNT
	_ammo[GUEST_PEER_ID] = REFILL_AMOUNT
	_facing[HOST_PEER_ID] = 1.0
	_facing[GUEST_PEER_ID] = -1.0
	for zone in get_tree().get_nodes_in_group("bubble_refill"):
		if zone is Area2D:
			zone.body_entered.connect(_on_refill_body_entered)


func _step_level(delta: float) -> void:
	bounce_mode.tick(delta)
	_update_facing()
	_update_bubbles(delta)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_try_fire_bubbles()


func _update_facing() -> void:
	for hero in [rabbit, fox]:
		var peer_id: int = int(hero.get_meta("peer_id", 0))
		if peer_id == 0:
			continue
		if hero.velocity.x > 1.0:
			_facing[peer_id] = 1.0
		elif hero.velocity.x < -1.0:
			_facing[peer_id] = -1.0


func _try_fire_bubbles() -> void:
	for hero in [_local_hero(), _remote_hero()]:
		if not hero.consume_action():
			continue
		var peer_id: int = int(hero.get_meta("peer_id", 0))
		_fire_bubble(peer_id, hero.global_position, _facing.get(peer_id, 1.0))


func _fire_bubble(owner_id: int, origin: Vector2, direction: float) -> void:
	if _bubbles.size() >= MAX_BUBBLES:
		return
	var ammo: int = int(_ammo.get(owner_id, 0))
	if ammo <= 0:
		return
	_ammo[owner_id] = ammo - 1
	_bubble_id_counter += 1
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
		"id": "bubble-%d" % _bubble_id_counter,
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
		if _check_bubble_hit(node, entry["owner_id"], entry["id"], entry["origin"]):
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
		if bubble.global_position.distance_to(hero.global_position) > BUBBLE_RADIUS + HIT_RADIUS:
			continue
		var knockback: Dictionary = bounce_mode.register_hit(owner_id, target_id, bubble_id, bounce_mode.time_remaining(), origin, hero.global_position)
		if not knockback.is_empty():
			hero.velocity = knockback["velocity"]
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
