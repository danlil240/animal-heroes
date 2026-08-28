class_name BubbleBounceMode
extends RefCounted

const MatchResultScript = preload("res://modes/match_result.gd")

const HIT_PROTECTION_TIME: float = 1.25
const MAX_HORIZONTAL_KNOCKBACK: float = 260.0
const MAX_VERTICAL_KNOCKBACK: float = 180.0
const DEFAULT_DURATION: float = 180.0
const BASE_KNOCKBACK_HORIZONTAL: float = 220.0
const BASE_KNOCKBACK_VERTICAL: float = 140.0

signal hit_registered(owner_id: int, target_id: int, projectile_id: String, knockback: Dictionary)
signal match_completed(result)

var _started: bool = false
var _finished: bool = false
var _time_remaining: float = 0.0
var _scores: Dictionary = {}
var _used_projectile_ids: Dictionary = {}
var _target_protection_deadline: Dictionary = {}


func start(duration: float = DEFAULT_DURATION) -> void:
	_started = true
	_finished = false
	_time_remaining = maxf(duration, 0.0)
	_scores.clear()
	_used_projectile_ids.clear()
	_target_protection_deadline.clear()


func register_hit(owner_id: int, target_id: int, projectile_id: String, host_time: float, owner_pos: Vector2 = Vector2.ZERO, target_pos: Vector2 = Vector2.ZERO) -> Dictionary:
	if not _started or _finished:
		return {}
	if owner_id == target_id:
		return {}
	if projectile_id.is_empty():
		return {}
	if _used_projectile_ids.has(projectile_id):
		return {}
	var deadline: float = float(_target_protection_deadline.get(target_id, -1.0))
	if host_time < deadline:
		return {}
	_used_projectile_ids[projectile_id] = true
	_target_protection_deadline[target_id] = host_time + HIT_PROTECTION_TIME
	_scores[owner_id] = _scores.get(owner_id, 0) + 1
	var knockback := _calculate_knockback(owner_pos, target_pos, owner_id, target_id)
	var info := {"velocity": knockback, "owner_id": owner_id, "target_id": target_id, "projectile_id": projectile_id}
	hit_registered.emit(owner_id, target_id, projectile_id, info)
	return info


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


func to_dict() -> Dictionary:
	return {
		"started": _started,
		"finished": _finished,
		"time_remaining": _time_remaining,
		"scores": _scores.duplicate(),
		"used_projectile_ids": _used_projectile_ids.duplicate(),
		"target_protection_deadline": _target_protection_deadline.duplicate(),
	}


func _calculate_knockback(owner_pos: Vector2, target_pos: Vector2, owner_id: int, target_id: int) -> Vector2:
	var direction: Vector2
	if owner_pos != target_pos:
		direction = (target_pos - owner_pos).normalized()
	else:
		direction = Vector2(1.0 if target_id > owner_id else -1.0, 0.0)
	var vel := Vector2(direction.x * BASE_KNOCKBACK_HORIZONTAL, direction.y * BASE_KNOCKBACK_VERTICAL)
	vel.x = clampf(vel.x, -MAX_HORIZONTAL_KNOCKBACK, MAX_HORIZONTAL_KNOCKBACK)
	vel.y = clampf(vel.y, -MAX_VERTICAL_KNOCKBACK, MAX_VERTICAL_KNOCKBACK)
	return vel


func _finish_match() -> void:
	if _finished:
		return
	_finished = true
	var result = finalize()
	match_completed.emit(result)
