class_name TreasureDashArena
extends CompetitionArena

## Timed collection match: the arena spawns host-owned collectibles from the
## mode's bounded seeded bag and scores fruit, gems, and stars.

const TreasureDashModeScript := preload("res://modes/treasure_dash_mode.gd")

const MATCH_DURATION: float = 180.0
const SPAWN_INTERVAL: float = 2.0
const MAX_ACTIVE_ITEMS: int = 24
const COLLECTIBLE_COLORS := {
	"fruit": Color(0.9, 0.3, 0.25, 1),
	"gem": Color(0.3, 0.8, 0.95, 1),
	"star": Color(1, 0.87, 0.15, 1),
}

@onready var collectibles_layer = $Collectibles
@onready var _hud = $HUD/TreasureDashHud

var dash_mode: RefCounted = null

var _spawn_timer: float = 0.0
var _collectible_nodes: Dictionary = {}


func _setup_arena() -> void:
	dash_mode = TreasureDashModeScript.new()
	dash_mode.start(MATCH_DURATION)
	dash_mode.configure_spawns(_collect_spawn_points(), MAX_ACTIVE_ITEMS)
	dash_mode.match_completed.connect(_finish_match)


func _step_level(delta: float) -> void:
	dash_mode.tick(delta)
	_spawn_timer += delta
	if _spawn_timer >= SPAWN_INTERVAL and not dash_mode.is_finished():
		_spawn_timer = 0.0
		_try_spawn_collectible()
	_hud.render(
		dash_mode.time_remaining(),
		dash_mode.score(HOST_PEER_ID),
		dash_mode.score(GUEST_PEER_ID),
	)


func _collect_spawn_points() -> Array:
	var points: Array = []
	for marker in get_tree().get_nodes_in_group("td_spawn_point"):
		points.append(marker.global_position)
	return points


func _try_spawn_collectible() -> void:
	var collectible_id: String = dash_mode.try_spawn(_local_hero().global_position, _remote_hero().global_position)
	if collectible_id.is_empty():
		return
	var type: String = dash_mode.spawn_type(collectible_id)
	var node := Area2D.new()
	node.position = dash_mode.spawn_position(collectible_id)
	node.add_to_group("td_collectible")
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(24, 24)
	shape.shape = rect
	node.add_child(shape)
	node.add_child(_make_collectible_art(type))
	node.body_entered.connect(_on_collectible_body_entered.bind(collectible_id, type))
	collectibles_layer.add_child(node)
	_collectible_nodes[collectible_id] = node


func _make_collectible_art(type: String) -> Polygon2D:
	var art := Polygon2D.new()
	art.polygon = _star_polygon()
	art.color = COLLECTIBLE_COLORS.get(type, Color(0.8, 0.8, 0.8, 1))
	return art


func _on_collectible_body_entered(body: Node, collectible_id: String, type: String) -> void:
	if not body.has_method("respawn"):
		return
	var peer_id: int = int(body.get_meta("peer_id", 0))
	if peer_id == 0:
		return
	if not dash_mode.collect(peer_id, collectible_id, type):
		return
	var node = _collectible_nodes.get(collectible_id)
	if node != null:
		node.queue_free()
		_collectible_nodes.erase(collectible_id)


func _star_polygon() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0, -12), Vector2(5, -4), Vector2(12, -4), Vector2(6, 2), Vector2(8, 11),
		Vector2(0, 7), Vector2(-8, 11), Vector2(-6, 2), Vector2(-12, -4), Vector2(-5, -4),
	])
