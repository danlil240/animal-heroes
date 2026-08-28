extends SceneTree


func _init() -> void:
	var mode_script = load("res://modes/treasure_dash_mode.gd")
	if mode_script == null:
		_fail("treasure_dash_mode.gd must exist")
		return

	# Case 1: scoring, duplicate rejection, and timer expiry from the plan.
	var mode = mode_script.new()
	mode.start(180.0)
	mode.collect(1, "fruit-1", "fruit")
	mode.collect(1, "fruit-1", "fruit")
	mode.collect(2, "star-1", "star")
	mode.tick(180.0)
	mode.collect(1, "gem-after-time", "gem")
	if mode.score(1) != 1:
		_fail("peer 1 score must be 1 (fruit only, duplicate rejected), got %d" % mode.score(1))
		return
	if mode.score(2) != 5:
		_fail("peer 2 score must be 5 (star), got %d" % mode.score(2))
		return
	if not mode.is_finished():
		_fail("mode must be finished after timer expires")
		return

	# Case 2: gem values and all three collectible types.
	mode = mode_script.new()
	mode.start(120.0)
	mode.collect(1, "fruit-a", "fruit")
	mode.collect(1, "gem-a", "gem")
	mode.collect(1, "star-a", "star")
	mode.collect(2, "fruit-b", "fruit")
	mode.collect(2, "gem-b", "gem")
	if mode.score(1) != 9:
		_fail("peer 1 score must be 1+3+5=9, got %d" % mode.score(1))
		return
	if mode.score(2) != 4:
		_fail("peer 2 score must be 1+3=4, got %d" % mode.score(2))
		return

	# Case 3: invalid collectible types are rejected.
	mode = mode_script.new()
	mode.start(60.0)
	mode.collect(1, "bad-1", "invalid_type")
	if mode.score(1) != 0:
		_fail("invalid collectible type must be rejected, got score %d" % mode.score(1))
		return

	# Case 4: finalize produces a MatchResult with correct winner.
	mode = mode_script.new()
	mode.start(90.0)
	mode.collect(1, "fruit-1", "fruit")
	mode.collect(2, "star-1", "star")
	mode.collect(2, "gem-1", "gem")
	mode.tick(90.0)
	var result = mode.finalize()
	if result == null:
		_fail("finalize must return a MatchResult")
		return
	if result.winner_peer_id != 2:
		_fail("winner must be peer 2 (score 8 vs 1), got %d" % result.winner_peer_id)
		return
	if result.scores.get(1, 0) != 1 or result.scores.get(2, 0) != 8:
		_fail("finalize scores must match, got %s" % str(result.scores))
		return

	# Case 5: reset clears all state.
	mode = mode_script.new()
	mode.start(30.0)
	mode.collect(1, "fruit-1", "fruit")
	mode.tick(30.0)
	mode.reset()
	if mode.is_finished() or mode.score(1) != 0:
		_fail("reset must clear all state")
		return

	# Case 6: bounded spawning keeps at most 24 active items.
	mode = mode_script.new()
	mode.start(180.0)
	mode.configure_spawns(_make_spawn_points(40), 24)
	for i in 40:
		mode.try_spawn(Vector2(1000 + i * 10, 500), Vector2(100, 500))
	if mode.active_spawn_count() > 24:
		_fail("active spawns must not exceed 24, got %d" % mode.active_spawn_count())
		return

	quit(0)


func _make_spawn_points(count: int) -> Array:
	var points: Array = []
	for i in count:
		points.append(Vector2(200 + i * 80, 500))
	return points


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
