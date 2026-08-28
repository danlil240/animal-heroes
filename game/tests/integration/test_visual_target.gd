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
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
