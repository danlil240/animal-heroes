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
	if not _test_reward_presentation():
		return
	if not await _test_hero_presentation():
		return
	if not _test_indicator_presentation():
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


func _test_reward_presentation() -> bool:
	var star_scene: PackedScene = load("res://visual/star_collectible_visual.tscn")
	var checkpoint_scene: PackedScene = load("res://visual/checkpoint_visual.tscn")
	if star_scene == null or checkpoint_scene == null:
		return _fail_bool("star and checkpoint visual scenes must load")
	var arena = load("res://levels/test_arena.tscn").instantiate()
	root.add_child(arena)
	var collectibles: Array[Node] = arena.get_node("Collectibles").get_children()
	if collectibles.size() != 10:
		return _fail_bool("visual conversion must preserve exactly ten collectible markers")
	for star in collectibles:
		if not star.is_in_group("arena_collectible") or star.get_node_or_null("Visual") == null:
			return _fail_bool("every collectible marker must keep its group and gain a Visual child")
	if arena.get_node_or_null("Checkpoint/Visual") == null:
		return _fail_bool("checkpoint must gain a separate Visual child")
	arena.queue_free()
	return true


func _test_hero_presentation() -> bool:
	var visual_scene: PackedScene = load("res://visual/hero_visual.tscn")
	if visual_scene == null:
		return _fail_bool("hero visual scene must load")
	var arena = load("res://levels/test_arena.tscn").instantiate()
	root.add_child(arena)
	await process_frame
	for hero_name in ["Rabbit", "Fox"]:
		var hero: CharacterBody2D = arena.get_node(hero_name)
		var visual = hero.get_node_or_null("Visual")
		if visual == null or hero.get_node_or_null("CollisionShape2D") == null or hero.get_node_or_null("Camera2D") == null:
			return _fail_bool("%s must keep gameplay nodes and gain a Visual child" % hero_name)
		if hero.get_node_or_null("BodyArt") != null:
			return _fail_bool("%s must not retain placeholder body art" % hero_name)
		var before_position := hero.position
		var before_velocity := hero.velocity
		visual._process(1.0 / 30.0)
		if hero.position != before_position or hero.velocity != before_velocity:
			return _fail_bool("hero presentation must not mutate %s physics state" % hero_name)
	arena.queue_free()
	return true


func _test_indicator_presentation() -> bool:
	var arena = load("res://levels/test_arena.tscn").instantiate()
	root.add_child(arena)
	var indicator: Control = arena.get_node("HUD/PartnerIndicator")
	if indicator.get_node_or_null("Outline") == null:
		return _fail_bool("partner indicator must have an outlined silhouette")
	var arrow := indicator.get_node("Arrow") as Polygon2D
	if arrow.color == Color(1.0, 0.35, 0.08, 1.0):
		return _fail_bool("partner indicator must use the shared gold reward language")
	arena.queue_free()
	return true


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _fail_bool(message: String) -> bool:
	_fail(message)
	return false
