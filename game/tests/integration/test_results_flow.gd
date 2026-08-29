extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var screen_scene = load("res://ui/results_screen.tscn")
	if screen_scene == null:
		_fail("results_screen.tscn must exist")
		return
	var screen = screen_scene.instantiate()
	root.add_child(screen)
	await process_frame

	# Case 1: basic rematch flow from the plan.
	screen.show_result({"winner_peer_id": 1, "scores": {1: 5, 2: 3}})
	screen.choose_rematch(1)
	if screen.rematch_ready():
		_fail("rematch must not be ready with only one peer")
		return
	screen.choose_rematch(2)
	if not screen.rematch_ready():
		_fail("rematch must be ready when both peers choose rematch")
		return
	if screen.displayed_scores.size() != 2 or int(screen.displayed_scores.get(1, 0)) != 5 or int(screen.displayed_scores.get(2, 0)) != 3:
		_fail("displayed_scores must match input, got %s" % str(screen.displayed_scores))
		return

	# Case 2: reset clears rematch state and scores.
	screen.reset()
	if screen.rematch_ready():
		_fail("reset must clear rematch ready state")
		return
	if screen.displayed_scores.size() != 0:
		_fail("reset must clear displayed scores, got %s" % str(screen.displayed_scores))
		return

	# Case 3: five rematch cycles leave no stale state.
	for cycle in 5:
		screen.show_result({"winner_peer_id": 2, "scores": {1: cycle, 2: cycle + 1}})
		screen.choose_rematch(1)
		screen.choose_rematch(2)
		if not screen.rematch_ready():
			_fail("rematch cycle %d must be ready" % cycle)
			return
		if int(screen.displayed_scores.get(2, 0)) != cycle + 1:
			_fail("cycle %d displayed_scores must be fresh, got %s" % [cycle, str(screen.displayed_scores)])
			return
		screen.reset()

	# Case 4: un-choosing rematch cancels readiness.
	screen.show_result({"winner_peer_id": 1, "scores": {1: 3, 2: 3}})
	screen.choose_rematch(1)
	screen.choose_rematch(2)
	if not screen.rematch_ready():
		_fail("both peers choosing rematch must be ready")
		return
	screen.cancel_rematch(1)
	if screen.rematch_ready():
		_fail("cancel_rematch must clear readiness")
		return

	# Case 5: winner_peer_id is accessible.
	screen.reset()
	screen.show_result({"winner_peer_id": 2, "scores": {1: 1, 2: 5}})
	if screen.winner_peer_id != 2:
		_fail("winner_peer_id must be 2, got %d" % screen.winner_peer_id)
		return

	# Case 6: cooperative results show one shared scoreboard and collected stars.
	screen.show_result({"winner_peer_id": 0, "scores": {}, "team_score": 235, "stars_collected": 7})
	if screen.displayed_team_score != 235 or screen.displayed_stars != 7:
		_fail("cooperative result must retain shared team score and stars")
		return
	var result_text := ""
	for label in screen.get_node("Margin/VBox/Scores").get_children():
		result_text += String(label.text)
	if not result_text.contains("235") or not result_text.contains("7"):
		_fail("cooperative scoreboard must visibly show team score and stars")
		return

	screen.queue_free()
	await process_frame
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
