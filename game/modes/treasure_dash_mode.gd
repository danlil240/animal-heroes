class_name TreasureDashMode
extends RefCounted

const MatchResultScript = preload("res://modes/match_result.gd")

const MAX_ACTIVE_ITEMS: int = 24
const SPAWN_EXCLUSION_RADIUS: float = 160.0
const COLLECTIBLE_VALUES: Dictionary = {"fruit": 1, "gem": 3, "star": 5}
const DEFAULT_DURATION: float = 180.0

signal collectible_collected(peer_id: int, collectible_id: String, type: String, value: int)
signal match_completed(result)

var _started: bool = false
var _finished: bool = false
var _time_remaining: float = 0.0
var _scores: Dictionary = {}
var _collected_ids: Dictionary = {}
var _spawn_points: Array = []
var _max_active: int = MAX_ACTIVE_ITEMS
var _active_spawns: Dictionary = {}
var _spawn_bag: Array = []
var _spawn_bag_index: int = 0
var _seed: int = 0


func start(duration: float = DEFAULT_DURATION) -> void:
	_started = true
	_finished = false
	_time_remaining = maxf(duration, 0.0)
	_scores.clear()
	_collected_ids.clear()
	_active_spawns.clear()
	_spawn_bag.clear()
	_spawn_bag_index = 0
	_seed = 0


func configure_spawns(points: Array, max_active: int = MAX_ACTIVE_ITEMS) -> void:
	_spawn_points = points.duplicate()
	_max_active = maxi(max_active, 1)
	_rebuild_spawn_bag()


func set_seed(seed_value: int) -> void:
	_seed = seed_value
	_rebuild_spawn_bag()


func collect(peer_id: int, collectible_id: String, type: String) -> bool:
	if not _started or _finished or collectible_id.is_empty():
		return false
	if not COLLECTIBLE_VALUES.has(type):
		return false
	if _collected_ids.has(collectible_id):
		return false
	var value: int = COLLECTIBLE_VALUES[type]
	_collected_ids[collectible_id] = true
	_scores[peer_id] = _scores.get(peer_id, 0) + value
	_active_spawns.erase(collectible_id)
	collectible_collected.emit(peer_id, collectible_id, type, value)
	return true


func tick(delta: float) -> void:
	if not _started or _finished:
		return
	_time_remaining -= maxf(delta, 0.0)
	if _time_remaining <= 0.0:
		_time_remaining = 0.0
		_finish_match()


func score(peer_id: int) -> int:
	return int(_scores.get(peer_id, 0))


func is_finished() -> bool:
	return _finished


func time_remaining() -> float:
	return _time_remaining


func finalize() -> RefCounted:
	var winner_peer_id: int = 0
	var best_score: int = -1
	for peer_id in _scores:
		var s: int = int(_scores[peer_id])
		if s > best_score:
			best_score = s
			winner_peer_id = int(peer_id)
	var result = MatchResultScript.new(winner_peer_id, _scores, [], "completed")
	return result


func reset() -> void:
	start(DEFAULT_DURATION)


func try_spawn(player_a: Vector2, player_b: Vector2) -> String:
	if not _started or _finished:
		return ""
	if _active_spawns.size() >= _max_active:
		return ""
	if _spawn_points.is_empty():
		return ""
	var point: Vector2 = _next_spawn_point()
	if point == Vector2.ZERO and _spawn_points.size() > 0:
		return ""
	var attempts: int = 0
	var max_attempts: int = _spawn_points.size()
	while _is_near_player(point, player_a, player_b) and attempts < max_attempts:
		point = _next_spawn_point()
		attempts += 1
	var collectible_id := "td-%d" % (_active_spawns.size() + _collected_ids.size() + 1)
	_active_spawns[collectible_id] = {"position": point, "type": _random_type()}
	return collectible_id


func active_spawn_count() -> int:
	return _active_spawns.size()


func active_spawn_ids() -> Array:
	return _active_spawns.keys()


func spawn_position(collectible_id: String) -> Vector2:
	var entry: Dictionary = _active_spawns.get(collectible_id, {})
	return entry.get("position", Vector2.ZERO)


func spawn_type(collectible_id: String) -> String:
	var entry: Dictionary = _active_spawns.get(collectible_id, {})
	return entry.get("type", "")


func to_dict() -> Dictionary:
	return {
		"started": _started,
		"finished": _finished,
		"time_remaining": _time_remaining,
		"scores": _scores.duplicate(),
		"collected_ids": _collected_ids.duplicate(),
		"active_spawns": _active_spawns.size(),
	}


func _finish_match() -> void:
	if _finished:
		return
	_finished = true
	var result = finalize()
	match_completed.emit(result)


func _rebuild_spawn_bag() -> void:
	_spawn_bag = _spawn_points.duplicate()
	_spawn_bag_index = 0
	if _spawn_bag.size() > 1:
		_seeded_shuffle(_spawn_bag)


func _seeded_shuffle(arr: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed if _seed != 0 else 1
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func _next_spawn_point() -> Vector2:
	if _spawn_bag.is_empty():
		return Vector2.ZERO
	var point: Vector2 = _spawn_bag[_spawn_bag_index % _spawn_bag.size()]
	_spawn_bag_index += 1
	return point


func _is_near_player(point: Vector2, player_a: Vector2, player_b: Vector2) -> bool:
	return point.distance_to(player_a) < SPAWN_EXCLUSION_RADIUS or point.distance_to(player_b) < SPAWN_EXCLUSION_RADIUS


func _random_type() -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed + _spawn_bag_index + _active_spawns.size()
	var roll: int = rng.randi_range(0, 9)
	if roll < 5:
		return "fruit"
	elif roll < 8:
		return "gem"
	return "star"
