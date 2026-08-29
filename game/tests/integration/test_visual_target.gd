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
	if not _test_gameplay_hud_presentation():
		return
	if not await _test_coop_hud_presence():
		return
	if not await _test_boss_overlay_presence():
		return
	if not _test_complete_arena_composition():
		return
	if not await _test_ground_art_covers_collider():
		return
	quit(0)


## Every walkable collider has to be drawn end to end. The ground art is a fixed
## 1600 px sprite while the ground colliders run up to 3400 px, so an uncovered
## collider leaves the heroes standing and walking on invisible ground.
func _test_ground_art_covers_collider() -> bool:
	for level_path in [
		"res://levels/sunny_forest.tscn",
		"res://levels/crystal_caves.tscn",
		"res://levels/cloud_factory.tscn",
		"res://levels/robot_boss.tscn",
		"res://levels/star_race_arena.tscn",
		"res://levels/treasure_dash_arena.tscn",
		"res://levels/bubble_bounce_arena.tscn",
		"res://levels/test_arena.tscn",
	]:
		var level = load(level_path).instantiate()
		root.add_child(level)
		await process_frame
		var ground: StaticBody2D = level.get_node("Ground")
		var shape: CollisionShape2D = ground.get_node("CollisionShape2D")
		var size: Vector2 = (shape.shape as RectangleShape2D).size
		var art: Sprite2D = ground.get_node("Visual").get_node("Ground")
		var art_width: float = art.texture.get_width() * art.global_scale.x
		var collider_left: float = shape.global_position.x - size.x * 0.5
		var collider_right: float = shape.global_position.x + size.x * 0.5
		var art_left: float = art.global_position.x - art_width * 0.5
		var art_right: float = art.global_position.x + art_width * 0.5
		var uncovered := art_left > collider_left + 0.5 or art_right < collider_right - 0.5
		level.queue_free()
		if uncovered:
			return _fail_bool("%s ground art (x %.0f..%.0f) must cover its collider (x %.0f..%.0f)" % [
				level_path.get_file(), art_left, art_right, collider_left, collider_right,
			])
	return true


func _test_background_parallax() -> bool:
	var background_scene: PackedScene = load("res://visual/sunny_forest_background.tscn")
	if background_scene == null:
		return _fail_bool("sunny forest background scene must load")
	var background = background_scene.instantiate()
	root.add_child(background)
	await process_frame
	for layer_name in ["Sky", "Far", "Mid", "Near", "Frame"]:
		if background.get_node_or_null(layer_name) == null:
			return _fail_bool("sunny forest background is missing %s" % layer_name)
	background.set_focus_x(400.0)
	if is_equal_approx(background.get_node("Far").position.x, background.get_node("Mid").position.x):
		return _fail_bool("far and mid forest layers must use different parallax ratios")
	if is_equal_approx(background.get_node("Mid").position.x, background.get_node("Near").position.x):
		return _fail_bool("mid and near forest layers must use different parallax ratios")
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
		if not visual.has_method("play_celebration") or not visual.has_method("play_damage"):
			return _fail_bool("%s visual must expose celebration and damage poses" % hero_name)
		# The art has to stand on the same line the collision box rests on,
		# otherwise the hero reads as floating above the ground.
		var shape: CollisionShape2D = hero.get_node("CollisionShape2D")
		var box_bottom: float = shape.global_position.y + (shape.shape as RectangleShape2D).size.y * 0.5
		var art: Sprite2D = visual.get_node("Pose/RabbitArt" if hero_name == "Rabbit" else "Pose/FoxArt")
		var art_bottom: float = art.global_position.y + art.texture.get_height() * art.global_scale.y * 0.5
		if absf(box_bottom - art_bottom) > 1.0:
			return _fail_bool("%s art must rest on the ground line, not float (gap %.1f px)" % [hero_name, box_bottom - art_bottom])
		var before_position := hero.position
		var before_velocity := hero.velocity
		visual._process(1.0 / 30.0)
		if hero.position != before_position or hero.velocity != before_velocity:
			return _fail_bool("hero presentation must not mutate %s physics state" % hero_name)
	arena.queue_free()
	for visual_path in [
		"res://visual/magical_tree_visual.tscn",
		"res://art/objects/fallen_log.svg",
		"res://art/objects/pressure_flower.svg",
		"res://art/objects/bubble_flower.svg",
	]:
		if load(visual_path) == null:
			return _fail_bool("storybook gameplay visual must load: %s" % visual_path)
	for enemy_path in ["res://world/beetle_enemy.tscn", "res://world/seed_enemy.tscn"]:
		var enemy = load(enemy_path).instantiate()
		if not enemy.get_node("Visual").has_method("show_enemy_state"):
			return _fail_bool("enemy art must animate readable movement and defeat states: %s" % enemy_path)
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


## Catches the shared score or either player's health disappearing from one
## tablet, and catches bubble ammo allocating beyond its five visible slots.
func _test_gameplay_hud_presentation() -> bool:
	var hud_scene: PackedScene = load("res://ui/gameplay_hud.tscn")
	if hud_scene == null:
		return _fail_bool("gameplay HUD scene must load")
	var hud = hud_scene.instantiate()
	root.add_child(hud)
	hud.render(135, 2, 3, 4)
	if hud.get_node("Top/Score").text != "135":
		return _fail_bool("HUD must display authoritative team score")
	if hud.get_node("Top/RabbitHearts").text != "♥♥♡":
		return _fail_bool("HUD must display Riki's current hearts")
	if hud.get_node("Top/FoxHearts").text != "♥♥♥♡":
		return _fail_bool("HUD must retain Foxy's fourth heart slot")
	var ammo_marks: Array[Node] = hud.get_node("Ammo/Marks").get_children()
	if ammo_marks.size() != 5:
		return _fail_bool("HUD must precreate exactly five bubble ammo marks")
	for index in ammo_marks.size():
		if ammo_marks[index].visible != (index < 4):
			return _fail_bool("HUD bubble marks must match local ammunition")
	hud.show_context("push")
	if not hud.get_node("Context").visible or hud.get_node("Context/Icon").text != "↔":
		return _fail_bool("HUD must show the push context without moving controls")
	hud.queue_free()
	return true


func _test_coop_hud_presence() -> bool:
	for level_path in [
		"res://levels/cloud_factory.tscn",
		"res://levels/crystal_caves.tscn",
		"res://levels/robot_boss.tscn",
	]:
		var level = load(level_path).instantiate()
		root.add_child(level)
		await process_frame
		var hud = level.get_node_or_null("HUD/GameplayHud")
		if hud == null:
			level.queue_free()
			return _fail_bool("%s must compose the coop GameplayHud" % level_path.get_file())
		if not hud.has_method("render"):
			level.queue_free()
			return _fail_bool("%s GameplayHud must expose render()" % level_path.get_file())
		level.queue_free()
	return true


func _test_boss_overlay_presence() -> bool:
	var level = load("res://levels/robot_boss.tscn").instantiate()
	root.add_child(level)
	await process_frame
	var overlay = level.get_node_or_null("HUD/BossStatusOverlay")
	if overlay == null:
		level.queue_free()
		return _fail_bool("robot_boss must compose the BossStatusOverlay")
	if not overlay.has_method("render"):
		level.queue_free()
		return _fail_bool("BossStatusOverlay must expose render()")
	level.queue_free()
	return true


func _test_complete_arena_composition() -> bool:
	var arena = load("res://levels/test_arena.tscn").instantiate()
	root.add_child(arena)
	var background := arena.get_node_or_null("SunnyForestBackground") as Node2D
	if background == null or background.z_index >= 0:
		return _fail_bool("arena must compose the sunny forest background behind gameplay")
	if arena.get_node("Collectibles").get_child_count() != 10:
		return _fail_bool("complete arena must preserve ten collectible markers")
	for hero_name in ["Rabbit", "Fox"]:
		var hero: CharacterBody2D = arena.get_node(hero_name)
		if hero.get_node_or_null("CollisionShape2D") == null or hero.get_node_or_null("Camera2D") == null or hero.get_node_or_null("Visual") == null:
			return _fail_bool("complete arena must preserve %s gameplay and presentation" % hero_name)
	var controls: Control = arena.get_node("HUD/TouchControls")
	for path in ["Movement/Left", "Movement/Right", "Jump", "Action"]:
		var target := controls.get_node(path) as Control
		if target.custom_minimum_size.x < 128.0 or target.custom_minimum_size.y < 128.0:
			return _fail_bool("%s must retain a 128 pixel touch target" % path)
	arena.queue_free()
	return true


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _fail_bool(message: String) -> bool:
	_fail(message)
	return false
