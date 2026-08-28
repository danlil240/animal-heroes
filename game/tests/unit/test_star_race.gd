extends SceneTree


func _init() -> void:
	var mode_script = load("res://modes/star_race_mode.gd")
	if mode_script == null:
		_fail("star_race_mode.gd must exist")
		return
	var result_script = load("res://modes/match_result.gd")
	if result_script == null:
		_fail("match_result.gd must exist")
		return

	# Case 1: finish order is recorded and duplicate finishes are ignored.
	var mode = mode_script.new()
	mode.start()
	_pass_all_checkpoints(mode, 2)
	_pass_all_checkpoints(mode, 1)
	mode.finish(2, 900.0)
	mode.finish(1, 901.0)
	mode.finish(2, 902.0)
	var result = mode.finalize()
	if result == null:
		_fail("finalize must return a MatchResult")
		return
	if result.winner_peer_id != 2:
		_fail("winner must be the first finisher (peer 2), got %d" % result.winner_peer_id)
		return
	if result.finish_order.size() != 2 or result.finish_order[0] != 2 or result.finish_order[1] != 1:
		_fail("finish_order must be [2, 1], got %s" % str(result.finish_order))
		return
	if result.scores.get(2, 0) <= result.scores.get(1, 0):
		_fail("winner score must exceed loser score, got %s" % str(result.scores))
		return

	# Case 2: grace period expires and finalizes with a single finisher.
	mode = mode_script.new()
	mode.start()
	_pass_all_checkpoints(mode, 1)
	mode.finish(1, 100.0)
	mode.tick(14.9, 100.0)
	if mode.is_finished():
		_fail("race must not finish before the 15s grace period elapses")
		return
	mode.tick(0.2, 100.0)
	if not mode.is_finished():
		_fail("race must finish after the 15s grace period elapses")
		return
	result = mode.finalize()
	if result.winner_peer_id != 1 or result.finish_order.size() != 1:
		_fail("grace-expired race must keep the single finisher, got winner=%d order=%s" % [result.winner_peer_id, str(result.finish_order)])
		return

	# Case 3: checkpoints must be passed in order; skipping is rejected.
	mode = mode_script.new()
	mode.start()
	if not mode.pass_checkpoint(1, "rcp-1", 0.0):
		_fail("first checkpoint in order must be accepted")
		return
	if mode.pass_checkpoint(1, "rcp-3", 0.0):
		_fail("skipping checkpoint rcp-3 must be rejected")
		return
	if not mode.pass_checkpoint(1, "rcp-2", 0.0):
		_fail("second checkpoint in order must be accepted")
		return
	if not mode.pass_checkpoint(1, "rcp-3", 0.0):
		_fail("third checkpoint in order must be accepted")
		return
	if not mode.pass_checkpoint(1, "rcp-4", 0.0):
		_fail("fourth checkpoint in order must be accepted")
		return
	if mode.pass_checkpoint(1, "rcp-1", 0.0):
		_fail("already-passed checkpoint must not be re-accepted out of order")
		return
	if not mode.has_passed_all_checkpoints(1):
		_fail("peer 1 must report all four checkpoints passed")
		return
	if mode.has_passed_all_checkpoints(2):
		_fail("peer 2 must not report all checkpoints passed")
		return

	# Case 4: finish before completing checkpoints is rejected.
	mode = mode_script.new()
	mode.start()
	mode.pass_checkpoint(1, "rcp-1", 0.0)
	mode.pass_checkpoint(1, "rcp-2", 0.0)
	mode.pass_checkpoint(1, "rcp-3", 0.0)
	mode.finish(1, 50.0)
	if mode.is_finished() or mode.finalize().finish_order.has(1):
		_fail("finish must be rejected until all four checkpoints are passed")
		return

	# Case 5: reset clears all state.
	mode = mode_script.new()
	mode.start()
	mode.pass_checkpoint(1, "rcp-1", 0.0)
	mode.finish(1, 10.0)
	mode.reset()
	if mode.is_finished() or mode.has_passed_all_checkpoints(1):
		_fail("reset must clear race state")
		return

	quit(0)


func _pass_all_checkpoints(mode, peer_id: int) -> void:
	for i in range(1, 5):
		mode.pass_checkpoint(peer_id, "rcp-%d" % i, 0.0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
