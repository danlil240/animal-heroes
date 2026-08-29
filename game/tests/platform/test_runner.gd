class_name TestRunner
extends SceneTree

const InputTimelineScript := preload("res://tests/platform/input_timeline.gd")
const PlayerInputScript := preload("res://player/player_input.gd")

const VIEWPORT_W := 1340
const VIEWPORT_H := 800
const SOFTLOCK_WINDOW := 180
const OUT_OF_WORLD_Y := 2000.0

var _test_name: String = "visual_test"
var _level_id: String = "sunny_forest"
var _timeline: InputTimelineScript = null
var _viewport: SubViewport = null
var _level: Node2D = null
var _rabbit: CharacterBody2D = null
var _fox: CharacterBody2D = null
var _injector: _InputInjector = null
var _out_dir: String = ""
var _result: Dictionary = {}
var _rabbit_history: Array[Vector2] = []
var _fox_history: Array[Vector2] = []


func _init() -> void:
	_read_args()
	call_deferred("_run")


func _read_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--test="):
			_test_name = arg.substr(7)
		elif arg.begins_with("--level="):
			_level_id = arg.substr(8)


# Subclasses override this to build the timeline.
func _build_timeline() -> InputTimelineScript:
	return InputTimelineScript.new(0)


func _level_scene_path() -> String:
	return "res://levels/%s.tscn" % _level_id


func _run() -> void:
	_init_result()
	_out_dir = "test-output/%s" % _test_name
	DirAccess.make_dir_recursive_absolute("res://%s" % _out_dir)
	_timeline = _build_timeline()
	_setup_viewport()
	if _level == null:
		_finish("fail", "SCENE_LOAD_FAILURE")
		return
	await process_frame  # let _ready fire
	_disable_auto_processing()
	await _run_loop()
	await process_frame
	_evaluate_end_assertions()
	_finish(_result.status, _result.failure_reason)


func _init_result() -> void:
	_result = {
		"test": _test_name,
		"level": _level_id,
		"status": "pass",
		"failure_reason": "none",
		"assertions": [],
		"captures": [],
		"alerts": [],
		"state_snapshots": [],
		"error_log": [],
	}


func _setup_viewport() -> void:
	var scene := load(_level_scene_path())
	if scene == null or not scene is PackedScene:
		push_error("cannot load level scene: %s" % _level_scene_path())
		return
	_level = scene.instantiate()
	if _level == null:
		push_error("cannot instantiate level scene")
		return
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(VIEWPORT_W, VIEWPORT_H)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.disable_3d = true
	_viewport.add_child(_level)
	get_root().add_child(_viewport)
	_rabbit = _level.get_node_or_null("Rabbit")
	_fox = _level.get_node_or_null("Fox")
	if _rabbit != null and _fox != null:
		_injector = _InputInjector.new()
		_injector.timeline = _timeline
		_injector.rabbit = _rabbit
		_injector.fox = _fox
		_level.add_child(_injector)
		_level.move_child(_injector, 0)


func _disable_auto_processing() -> void:
	if _level != null:
		for child in _level.get_children():
			_freeze_subtree_visuals(child)


# Freeze _process (real-time visual animations) on every node in the subtree,
# and freeze _physics_process on nodes that are NOT the heroes or the level's
# own physics (we want the engine to drive level._physics_process and the
# heroes' physics_step). Enemies/bubbles/areas have no meaningful
# _physics_process, so disabling theirs is harmless; their motion comes from
# host_step called in _step_level.
func _freeze_subtree_visuals(node: Node) -> void:
	node.set_process(false)
	# Keep heroes' _physics_process enabled (engine drives move_and_slide).
	# Keep the level's _physics_process enabled (drives _step_level + route_control).
	# Disable _physics_process on everything else (enemies, bubbles, areas, visuals).
	if node != _rabbit and node != _fox and node != _injector:
		node.set_physics_process(false)
	for child in node.get_children():
		_freeze_subtree_visuals(child)


func _run_loop() -> void:
	var total := _timeline.total_frames()
	var saved_hz := Engine.get_physics_ticks_per_second()
	Engine.set_max_physics_steps_per_frame(1)
	for frame in range(total + 1):
		_injector.current_frame = frame
		Engine.set_physics_ticks_per_second(saved_hz)
		await physics_frame
		Engine.set_physics_ticks_per_second(1)
		await process_frame
		_record_history()
		_run_bug_detection(frame)
		_run_frame_assertions(frame)
		_maybe_capture(frame)
		_record_state_snapshot(frame)
		if _result.status == "fail" and _result.failure_reason != "none":
			break
	Engine.set_physics_ticks_per_second(saved_hz)
	Engine.set_max_physics_steps_per_frame(8)


func _record_history() -> void:
	_rabbit_history.append(_rabbit.global_position)
	_fox_history.append(_fox.global_position)


func _run_bug_detection(frame: int) -> void:
	if _rabbit.global_position.y > OUT_OF_WORLD_Y or _fox.global_position.y > OUT_OF_WORLD_Y:
		_add_alert("out_of_world@frame %d" % frame)
		_fail("OUT_OF_WORLD")
	if frame >= SOFTLOCK_WINDOW:
		var r0 := _rabbit_history[frame - SOFTLOCK_WINDOW]
		var f0 := _fox_history[frame - SOFTLOCK_WINDOW]
		var r_moved := _rabbit.global_position.distance_to(r0) > 5.0
		var f_moved := _fox.global_position.distance_to(f0) > 5.0
		if not r_moved and not f_moved:
			_add_alert("softlock@frame %d" % frame)
			_fail("SOFTLOCK")


func _run_frame_assertions(frame: int) -> void:
	for a in _timeline.assertions():
		if not a.has("frame") or int(a.frame) != frame:
			continue
		_evaluate_assertion(a)


func _maybe_capture(frame: int) -> void:
	for c in _timeline.captures():
		if int(c.frame) != frame:
			continue
		var img := _viewport.get_texture().get_image()
		var render_ok := img != null
		var path := "%s/%s.png" % [_out_dir, c.name]
		if render_ok:
			var err := img.save_png("res://%s" % path)
			render_ok = err == OK
		else:
			_fail("RENDER_FAILURE")
		_result.captures.append({
			"name": c.name, "frame": frame, "path": "%s.png" % c.name, "render_ok": render_ok
		})
		# HUD presence check at capture frames
		var hud := _level.get_node_or_null("HUD/GameplayHud")
		if hud == null or not hud.visible:
			_add_alert("hud_missing@frame %d" % frame)


func _record_state_snapshot(frame: int) -> void:
	# Snapshot at capture frames and the final frame to keep result.json small.
	var is_capture := false
	for c in _timeline.captures():
		if int(c.frame) == frame:
			is_capture = true
			break
	if not is_capture and frame != _timeline.total_frames():
		return
	var score := 0
	if _level.has_method("get") and _level.get("team_score") != null:
		score = int(_level.get("team_score").total)
	_result.state_snapshots.append({
		"frame": frame,
		"rabbit": [_rabbit.global_position.x, _rabbit.global_position.y],
		"fox": [_fox.global_position.x, _fox.global_position.y],
		"score": score,
		"rabbit_hearts": int(_rabbit.hearts),
		"fox_hearts": int(_fox.hearts),
		"finished": _level.is_finished(),
	})


func _evaluate_end_assertions() -> void:
	for a in _timeline.assertions():
		if a.has("frame"):
			continue
		_evaluate_assertion(a)


func _evaluate_assertion(a: Dictionary) -> void:
	var kind: String = a.kind
	var args: Array = a.args
	var passed := true
	var message := ""
	var needs_log_scan := false
	var final_frame := _timeline.total_frames()
	match kind:
		"position_gt":
			var peer_id := int(args[0])
			var axis := String(args[1])
			var value := float(args[2])
			var hero := _hero_for(peer_id)
			var v := hero.global_position.x if axis == "x" else hero.global_position.y
			passed = v > value
			message = "peer %d %s=%.1f > %.1f" % [peer_id, axis, v, value]
		"position_lt":
			var peer_id := int(args[0])
			var axis := String(args[1])
			var value := float(args[2])
			var hero := _hero_for(peer_id)
			var v := hero.global_position.x if axis == "x" else hero.global_position.y
			passed = v < value
			message = "peer %d %s=%.1f < %.1f" % [peer_id, axis, v, value]
		"position_eq":
			var hero := _hero_for(int(args[0]))
			var x := float(args[1]); var y := float(args[2]); var tol := float(args[3])
			passed = hero.global_position.distance_to(Vector2(x, y)) <= tol
			message = "peer %d at %s vs (%.1f,%.1f) tol %.1f" % [int(args[0]), str(hero.global_position), x, y, tol]
		"score_eq":
			var ts: Variant = _level.get("team_score")
			passed = int(ts.total) == int(args[0])
			message = "score=%d == %d" % [int(ts.total), int(args[0])]
		"score_gt":
			var ts: Variant = _level.get("team_score")
			passed = int(ts.total) > int(args[0])
			message = "score=%d > %d" % [int(ts.total), int(args[0])]
		"gate_open":
			passed = _level.gate_is_open(String(args[0]))
			message = "gate %s open" % String(args[0])
		"gate_closed":
			passed = not _level.gate_is_open(String(args[0]))
			message = "gate %s closed" % String(args[0])
		"hearts_eq":
			var hero := _hero_for(int(args[0]))
			passed = int(hero.hearts) == int(args[1])
			message = "peer %d hearts=%d == %d" % [int(args[0]), int(hero.hearts), int(args[1])]
		"hearts_gt":
			var hero := _hero_for(int(args[0]))
			passed = int(hero.hearts) > int(args[1])
			message = "peer %d hearts=%d > %d" % [int(args[0]), int(hero.hearts), int(args[1])]
		"no_errors":
			passed = true
			needs_log_scan = true
			message = "no_errors (resolved by orchestrator log scan)"
		"both_alive":
			passed = int(_rabbit.hearts) > 0 and int(_fox.hearts) > 0
			message = "hearts rabbit=%d fox=%d" % [_rabbit.hearts, _fox.hearts]
		"finished":
			passed = _level.is_finished()
			message = "finished=%s" % str(_level.is_finished())
		"not_finished":
			passed = not _level.is_finished()
			message = "finished=%s" % str(_level.is_finished())
		"bubble_count_eq":
			passed = _level.active_bubble_count() == int(args[0])
			message = "bubbles=%d == %d" % [_level.active_bubble_count(), int(args[0])]
		"ammo_eq":
			var peer_id := int(args[0])
			var ammo: Variant = _level.get("bubble_ammo")
			passed = int(ammo.remaining(peer_id)) == int(args[1])
			message = "peer %d ammo=%d == %d" % [peer_id, int(ammo.remaining(peer_id)), int(args[1])]
		_:
			passed = false
			message = "unknown assertion kind: %s" % kind
	var entry := {"kind": kind, "args": args, "passed": passed, "message": message, "needs_log_scan": needs_log_scan}
	if a.has("frame"):
		entry["frame"] = int(a.frame)
	_result.assertions.append(entry)
	if not passed and not needs_log_scan:
		_fail("ASSERTION")


func _hero_for(peer_id: int) -> CharacterBody2D:
	return _rabbit if peer_id == 1 else _fox


func _add_alert(msg: String) -> void:
	_result.alerts.append(msg)


func _fail(reason: String) -> void:
	_result.status = "fail"
	_result.failure_reason = reason


func _finish(status: String, reason: String) -> void:
	_result.status = status
	_result.failure_reason = reason
	var f := FileAccess.open("res://%s/result.json" % _out_dir, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_result, "\t"))
		f.close()
	print("VISUAL_TEST_RESULT name=%s status=%s" % [_test_name, _result.status])
	quit(1 if _result.status == "fail" else 0)


class _InputInjector extends Node:
	var timeline: InputTimeline
	var rabbit: CharacterBody2D
	var fox: CharacterBody2D
	var current_frame: int = 0

	func _physics_process(_delta: float) -> void:
		if timeline == null or rabbit == null or fox == null:
			return
		rabbit.apply_input(timeline.frame_for(1, current_frame))
		fox.apply_input(timeline.frame_for(2, current_frame))
