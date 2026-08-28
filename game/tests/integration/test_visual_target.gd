extends SceneTree

const REQUIRED_COLORS := [
	"SKY_TOP",
	"SKY_BOTTOM",
	"INK",
	"GRASS_LIGHT",
	"GRASS_DARK",
	"ROCK_LIGHT",
	"ROCK_DARK",
	"STAR",
	"CONTROL_BLUE",
	"CONTROL_BORDER",
]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var palette: Script = load("res://theme/visual_palette.gd")
	var game_theme: Theme = load("res://theme/game_theme.tres")
	if palette == null or game_theme == null:
		_fail("visual palette and game theme must load")
		return
	var constants := palette.get_script_constant_map()
	for color_name in REQUIRED_COLORS:
		if not constants.has(color_name) or not constants[color_name] is Color:
			_fail("visual palette is missing color %s" % color_name)
			return
	if not game_theme.has_stylebox("normal", "Button") or not game_theme.has_stylebox("pressed", "Button"):
		_fail("game theme must style normal and pressed buttons")
		return
	var normal := game_theme.get_stylebox("normal", "Button") as StyleBoxFlat
	if normal == null or normal.corner_radius_top_left < 24 or normal.border_width_left < 3:
		_fail("game buttons must use large rounded corners and a visible border")
		return
	if not await _test_background_parallax():
		return
	if not _test_platform_presentation():
		return
	quit(0)


func _test_background_parallax() -> bool:
	var background_scene: PackedScene = load("res://visual/sunny_forest_background.tscn")
	if background_scene == null:
		return _fail_bool("sunny forest background scene must load")
	var background = background_scene.instantiate()
	root.add_child(background)
	await process_frame
	for layer_name in ["Sky", "Far", "Mid", "Frame"]:
		if background.get_node_or_null(layer_name) == null:
			return _fail_bool("sunny forest background is missing %s" % layer_name)
	background.set_focus_x(400.0)
	if is_equal_approx(background.get_node("Far").position.x, background.get_node("Mid").position.x):
		return _fail_bool("far and mid forest layers must use different parallax ratios")
	background.queue_free()
	return true


func _test_platform_presentation() -> bool:
	var arena_scene: PackedScene = load("res://levels/test_arena.tscn")
	var arena = arena_scene.instantiate()
	root.add_child(arena)
	for body_name in ["Ground", "PlatformA", "PlatformB", "PlatformC"]:
		var body := arena.get_node(body_name)
		if body.get_node_or_null("CollisionShape2D") == null or body.get_node_or_null("Visual") == null:
			return _fail_bool("%s must keep collision and gain a separate Visual child" % body_name)
		if body.get_node_or_null("GroundArt") != null or body.get_node_or_null("Art") != null:
			return _fail_bool("%s must not retain placeholder polygon art" % body_name)
	arena.queue_free()
	return true


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _fail_bool(message: String) -> bool:
	_fail(message)
	return false
