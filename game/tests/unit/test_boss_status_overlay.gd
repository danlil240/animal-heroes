extends SceneTree

const PHASE_TIME_LIMIT := 45.0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load("res://ui/boss_status_overlay.tscn")
	if scene == null:
		_fail("boss status overlay scene must load")
		return
	var overlay = scene.instantiate()
	root.add_child(overlay)
	await process_frame
	for required in ["PhaseLabel", "CycleLabel", "TimerBar", "TimerTrack"]:
		if overlay.get_node_or_null(required) == null:
			_fail("boss overlay must expose node %s" % required)
			return
	overlay.render("avoid", 0, 30.0)
	if overlay.get_node("PhaseLabel").text.is_empty():
		_fail("boss overlay must show a non-empty phase label for avoid")
		return
	if overlay.get_node("CycleLabel").text != "1/3":
		_fail("boss overlay cycle must read 1/3 for cycle_count 0, got %s" % overlay.get_node("CycleLabel").text)
		return
	var bar: ColorRect = overlay.get_node("TimerBar")
	var track: ColorRect = overlay.get_node("TimerTrack")
	var expected_fraction := clampf(30.0 / PHASE_TIME_LIMIT, 0.0, 1.0)
	if absf(bar.size.x - track.size.x * expected_fraction) > 1.0:
		_fail("boss overlay timer bar must reflect seconds left fraction")
		return
	overlay.render("defeated", 3, 0.0)
	if overlay.get_node("CycleLabel").text != "3/3":
		_fail("boss overlay cycle must read 3/3 when defeated, got %s" % overlay.get_node("CycleLabel").text)
		return
	overlay.queue_free()
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
