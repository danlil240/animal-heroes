class_name StarRaceMode
extends RefCounted

const MatchResultScript = preload("res://modes/match_result.gd")

signal peer_finished(peer_id: int, finish_tick: float)
signal race_completed(result)

const GRACE_PERIOD: float = 15.0
const CHECKPOINTS_PER_ROUTE: int = 4
const WIN_SCORE: int = 3
const PLACE_SCORES: Array[int] = [3, 1]

var _started: bool = false
var _finished: bool = false
var _finish_ticks: Dictionary = {}
var _finish_order: Array[int] = []
var _first_finish_tick: float = -1.0
var _grace_elapsed: float = 0.0
var _peer_checkpoint_index: Dictionary = {}
var _peer_checkpoint_ids: Dictionary = {}


func start() -> void:
	_started = true
	_finished = false
	_finish_ticks.clear()
	_finish_order.clear()
	_first_finish_tick = -1.0
	_grace_elapsed = 0.0
	_peer_checkpoint_index.clear()
	_peer_checkpoint_ids.clear()


func pass_checkpoint(peer_id: int, checkpoint_id: String, _host_tick: float) -> bool:
	if not _started or _finished:
		return false
	var index: int = _peer_checkpoint_index.get(peer_id, 0)
	# Checkpoints must be passed in order rcp-1, rcp-2, ..., rcp-N.
	var expected_id := "rcp-%d" % (index + 1)
	if checkpoint_id != expected_id:
		return false
	_peer_checkpoint_index[peer_id] = index + 1
	var ids: Array = _peer_checkpoint_ids.get(peer_id, [])
	ids.append(checkpoint_id)
	_peer_checkpoint_ids[peer_id] = ids
	return true


func has_passed_all_checkpoints(peer_id: int) -> bool:
	return _peer_checkpoint_index.get(peer_id, 0) >= CHECKPOINTS_PER_ROUTE


func checkpoint_progress(peer_id: int) -> int:
	return _peer_checkpoint_index.get(peer_id, 0)


func finish(peer_id: int, host_tick: float) -> void:
	if not _started or _finished or _finish_ticks.has(peer_id):
		return
	if not has_passed_all_checkpoints(peer_id):
		return
	_finish_ticks[peer_id] = host_tick
	_finish_order.append(peer_id)
	if _first_finish_tick < 0.0:
		_first_finish_tick = host_tick
	peer_finished.emit(peer_id, host_tick)
	_check_completion(host_tick)


func tick(delta: float, host_tick: float) -> void:
	if not _started or _finished or _first_finish_tick < 0.0:
		return
	_grace_elapsed += maxf(delta, 0.0)
	if _grace_elapsed >= GRACE_PERIOD:
		_finish_race(host_tick, "grace_expired")


func is_finished() -> bool:
	return _finished


func finalize() -> RefCounted:
	var scores: Dictionary = {}
	for i in _finish_order.size():
		var peer_id: int = _finish_order[i]
		scores[peer_id] = PLACE_SCORES[i] if i < PLACE_SCORES.size() else 0
	var winner: int = _finish_order[0] if _finish_order.size() > 0 else 0
	var reason := "completed" if _finish_order.size() >= 2 else "grace_expired"
	var result = MatchResultScript.new(winner, scores, _finish_order, reason)
	return result


func reset() -> void:
	start()


func to_dict() -> Dictionary:
	return {
		"started": _started,
		"finished": _finished,
		"finish_ticks": _finish_ticks.duplicate(),
		"finish_order": _finish_order.duplicate(),
		"first_finish_tick": _first_finish_tick,
		"grace_elapsed": _grace_elapsed,
		"peer_checkpoint_index": _peer_checkpoint_index.duplicate(),
	}


func _check_completion(host_tick: float) -> void:
	if _finish_order.size() >= 2:
		_finish_race(host_tick, "completed")


func _finish_race(_host_tick: float, reason: String) -> void:
	if _finished:
		return
	_finished = true
	var result = finalize()
	result.reason = reason
	race_completed.emit(result)
