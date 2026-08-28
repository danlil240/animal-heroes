extends SceneTree


func _init() -> void:
	var mode_script = load("res://modes/bubble_bounce_mode.gd")
	if mode_script == null:
		_fail("bubble_bounce_mode.gd must exist")
		return

	# Case 1: hit-protection from the plan.
	var mode = mode_script.new()
	mode.start(180.0)
	mode.register_hit(1, 2, "bubble-1", 0.0)
	mode.register_hit(1, 2, "bubble-2", 0.5)
	mode.register_hit(1, 1, "bubble-3", 2.0)
	mode.register_hit(1, 2, "bubble-4", 2.0)
	if mode.score(1) != 2:
		_fail("peer 1 score must be 2 (protection + self-hit rejected), got %d" % mode.score(1))
		return
	if mode.score(2) != 0:
		_fail("peer 2 score must be 0, got %d" % mode.score(2))
		return

	# Case 2: protection deadline is exactly 1.25 seconds.
	mode = mode_script.new()
	mode.start(180.0)
	mode.register_hit(1, 2, "bubble-1", 0.0)
	mode.register_hit(1, 2, "bubble-2", 1.24)
	if mode.score(1) != 1:
		_fail("hit within 1.25s protection must be rejected, got score %d" % mode.score(1))
		return
	mode.register_hit(1, 2, "bubble-3", 1.25)
	if mode.score(1) != 2:
		_fail("hit at exactly 1.25s must be accepted, got score %d" % mode.score(1))
		return

	# Case 3: duplicate projectile ID is rejected.
	mode = mode_script.new()
	mode.start(180.0)
	mode.register_hit(1, 2, "bubble-1", 0.0)
	mode.register_hit(2, 1, "bubble-1", 3.0)
	if mode.score(1) != 1 or mode.score(2) != 0:
		_fail("duplicate projectile id must be rejected, got scores %d/%d" % [mode.score(1), mode.score(2)])
		return

	# Case 4: hits after timer expires are rejected.
	mode = mode_script.new()
	mode.start(10.0)
	mode.register_hit(1, 2, "bubble-1", 0.0)
	mode.tick(10.0)
	mode.register_hit(1, 2, "bubble-2", 11.0)
	if mode.score(1) != 1:
		_fail("hit after timer expiry must be rejected, got score %d" % mode.score(1))
		return
	if not mode.is_finished():
		_fail("mode must be finished after timer expires")
		return

	# Case 5: finalize produces correct MatchResult.
	mode = mode_script.new()
	mode.start(30.0)
	mode.register_hit(1, 2, "b1", 0.0)
	mode.register_hit(2, 1, "b2", 2.0)
	mode.register_hit(2, 1, "b3", 4.0)
	mode.tick(30.0)
	var result = mode.finalize()
	if result == null:
		_fail("finalize must return a MatchResult")
		return
	if result.winner_peer_id != 2:
		_fail("winner must be peer 2 (score 2 vs 1), got %d" % result.winner_peer_id)
		return
	if result.scores.get(1, 0) != 1 or result.scores.get(2, 0) != 2:
		_fail("finalize scores must match, got %s" % str(result.scores))
		return

	# Case 6: knockback is clamped to bounded values.
	mode = mode_script.new()
	mode.start(60.0)
	var kb = mode.register_hit(1, 2, "kb-1", 0.0)
	if kb == null:
		_fail("register_hit must return knockback info")
		return
	if absf(kb.velocity.x) > 260.0 or absf(kb.velocity.y) > 180.0:
		_fail("knockback must be clamped to 260h/180v, got %s" % str(kb.velocity))
		return

	# Case 7: reset clears all state.
	mode = mode_script.new()
	mode.start(30.0)
	mode.register_hit(1, 2, "b1", 0.0)
	mode.tick(30.0)
	mode.reset()
	if mode.is_finished() or mode.score(1) != 0:
		_fail("reset must clear all state")
		return

	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
