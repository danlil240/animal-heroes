class_name LiveInspect
extends SceneTree

const PlayerInputScript := preload("res://player/player_input.gd")

const SCREENSHOT_DIR := "test-output/live"
const KNOWN_GATE_IDS := ["fallen-log", "bubble-grove"]

var _level_id: String = "sunny_forest"
var _script_fox: bool = false
var _self_test: bool = false
var _level: Node2D = null
var _rabbit: CharacterBody2D = null
var _fox: CharacterBody2D = null
var _injector: _InputInjector = null
var _paused: bool = false


func _init() -> void:
	_read_args()
	call_deferred("_run")


func _read_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--level="):
			_level_id = arg.substr(8)
		elif arg == "--script-fox":
			_script_fox = true
		elif arg == "--self-test":
			_self_test = true


func _level_scene_path() -> String:
	return "res://levels/%s.tscn" % _level_id


func _run() -> void:
	_setup_level()
	if _level == null:
		push_error("cannot load level scene: %s" % _level_scene_path())
		quit(1)
		return
	await process_frame  # let _ready fire
	# Do NOT disable any processing — the operator wants the real game loop
	# with real-time animations. The engine drives physics normally; the
	# injector re-applies keyboard input after route_control_frames overwrites
	# the local hero with empty touch.
	if _self_test:
		_capture_screenshot()
		_print_state()
		quit(0)
		return
	print("LIVE_INSPECT ready — F11=state F12=screenshot P=pause ESC=quit")
	await _interactive_loop()


func _setup_level() -> void:
	var scene := load(_level_scene_path())
	if scene == null or not scene is PackedScene:
		push_error("cannot load level scene: %s" % _level_scene_path())
		return
	_level = scene.instantiate()
	if _level == null:
		push_error("cannot instantiate level scene")
		return
	# Add to the visible root window (NOT a SubViewport) so the operator can
	# see and interact with the real game.
	get_root().add_child(_level)
	_rabbit = _level.get_node_or_null("Rabbit")
	_fox = _level.get_node_or_null("Fox")
	if _rabbit != null and _fox != null:
		_injector = _InputInjector.new()
		_injector.rabbit = _rabbit
		_injector.fox = _fox
		_injector.script_fox = _script_fox
		_level.add_child(_injector)
		_level.move_child(_injector, 0)


func _interactive_loop() -> void:
	while true:
		await process_frame
		if Input.is_key_pressed(KEY_ESCAPE):
			quit(0)
			return
		if Input.is_key_pressed(KEY_F12):
			_capture_screenshot()
		if Input.is_key_pressed(KEY_F11):
			_print_state()
		if Input.is_key_pressed(KEY_P):
			_toggle_pause()


func _capture_screenshot() -> void:
	DirAccess.make_dir_recursive_absolute("res://%s" % SCREENSHOT_DIR)
	var img := get_root().get_texture().get_image()
	if img == null:
		push_error("screenshot: root texture returned null image")
		return
	var timestamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := "res://%s/%s.png" % [SCREENSHOT_DIR, timestamp]
	var err := img.save_png(path)
	if err != OK:
		push_error("screenshot: save_png failed (%d)" % err)
		return
	print("SCREENSHOT saved: %s" % path)


func _print_state() -> void:
	print("--- LIVE INSPECT STATE ---")
	if _rabbit != null:
		print("rabbit pos=%s hearts=%d" % [str(_rabbit.global_position), int(_rabbit.hearts)])
	else:
		print("rabbit: <missing>")
	if _fox != null:
		print("fox pos=%s hearts=%d" % [str(_fox.global_position), int(_fox.hearts)])
	else:
		print("fox: <missing>")
	var score: Variant = _level.get("team_score") if _level != null else null
	if score != null:
		print("team_score total=%s" % str(score.total))
	if _level != null and _level.has_method("is_finished"):
		print("finished=%s" % str(_level.is_finished()))
	if _level != null and _level.has_method("gate_is_open"):
		for gate_id in KNOWN_GATE_IDS:
			if _level.gate_is_open(gate_id):
				print("gate %s: open" % gate_id)
			else:
				print("gate %s: closed" % gate_id)
	print("--------------------------")


func _toggle_pause() -> void:
	_paused = not _paused
	paused = _paused
	print("PAUSE %s" % ("on" if _paused else "off"))


class _InputInjector extends Node:
	var rabbit: CharacterBody2D
	var fox: CharacterBody2D
	var script_fox: bool = false
	var fox_axis: float = 1.0

	func _physics_process(_delta: float) -> void:
		if rabbit != null:
			var frame := PlayerInputScript.InputFrame.new()
			var axis := 0.0
			if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
				axis += 1.0
			if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
				axis -= 1.0
			frame.axis = axis
			frame.jump = Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_UP)
			frame.action = Input.is_key_pressed(KEY_E)
			rabbit.apply_input(frame)
		if fox != null and script_fox:
			var fframe := PlayerInputScript.InputFrame.new()
			fframe.axis = fox_axis
			fox.apply_input(fframe)
