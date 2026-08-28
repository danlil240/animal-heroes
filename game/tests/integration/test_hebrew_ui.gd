extends SceneTree

const TARGET_LAYOUTS := [Vector2(1340, 800), Vector2(1024, 600)]
const HOME_LABELS := ["משחק משותף", "תחרות", "איך משחקים", "הגדרות"]

var _menu_script: Script
var _touch_script: Script
var _tutorial_script: Script
var _created := 0
var _joined := 0
var _competition := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_menu_script = load("res://ui/main_menu.gd")
	_touch_script = load("res://ui/touch_controls.gd")
	_tutorial_script = load("res://ui/how_to_play.gd")
	if _menu_script == null or _touch_script == null or _tutorial_script == null:
		_fail("Hebrew UI scripts must exist")
		return
	for layout in TARGET_LAYOUTS:
		if not await _test_menu_layout(layout):
			return
		if not await _test_coop_layout(layout):
			return
		if not await _test_touch_layout(layout):
			return
	if not await _test_menu_actions_and_replacement():
		return
	if not await _test_tutorial_animation():
		return
	if not _test_tutorial_highlights():
		return
	if not await _test_simultaneous_touch_and_keyboard():
		return
	quit(0)


func _test_menu_layout(layout: Vector2) -> bool:
	var menu = load("res://ui/main_menu.tscn").instantiate()
	_prepare_layout(menu, layout)
	root.add_child(menu)
	await process_frame
	var choices: VBoxContainer = menu.get_node("Margin/VBox")
	var labels := [
		menu.get_node("Margin/VBox/Coop").text,
		menu.get_node("Margin/VBox/Competition").text,
		menu.get_node("Margin/VBox/HowTo").text,
		menu.get_node("Margin/VBox/Settings").text,
	]
	if labels != HOME_LABELS:
		return _fail_bool("Hebrew home labels must exactly match at %s" % layout)
	if menu.layout_direction != Control.LAYOUT_DIRECTION_RTL or menu.get_node("Margin").layout_direction != Control.LAYOUT_DIRECTION_RTL or choices.layout_direction != Control.LAYOUT_DIRECTION_RTL:
		return _fail_bool("Hebrew menu choice container must be RTL")
	for choice in choices.get_children():
		if choice is Control and ((choice as Control).size.x < 96.0 or (choice as Control).size.y < 96.0):
			return _fail_bool("home target %s must be at least 96 px at %s" % [choice.name, layout])
		if choice is Control and not _within(menu, choice):
			return _fail_bool("home target %s must not overflow at %s" % [choice.name, layout])
		if choice is Button and (choice as Button).get_combined_minimum_size().x > (choice as Button).size.x:
			return _fail_bool("Hebrew home label %s must not clip at %s" % [choice.name, layout])
	root.remove_child(menu)
	menu.queue_free()
	return true


func _test_coop_layout(layout: Vector2) -> bool:
	var menu = load("res://ui/main_menu.tscn").instantiate()
	_prepare_layout(menu, layout)
	root.add_child(menu)
	await process_frame
	menu.get_node("Margin/VBox/Coop").emit_signal("pressed")
	await process_frame
	var choices: VBoxContainer = menu.get_node("Margin/VBox")
	if choices.layout_direction != Control.LAYOUT_DIRECTION_RTL:
		return _fail_bool("cooperative choice container must remain RTL at %s" % layout)
	for choice in choices.get_children():
		if not (choice is Button) or minf((choice as Button).size.x, (choice as Button).size.y) < 96.0:
			return _fail_bool("cooperative target %s must be at least 96 px at %s" % [choice.name, layout])
		if not _within(menu, choice) or (choice as Button).get_combined_minimum_size().x > (choice as Button).size.x:
			return _fail_bool("cooperative choice %s must remain visible at %s" % [choice.name, layout])
	root.remove_child(menu)
	menu.queue_free()
	return true


func _test_touch_layout(layout: Vector2) -> bool:
	var controls = load("res://ui/touch_controls.tscn").instantiate()
	_prepare_layout(controls, layout)
	root.add_child(controls)
	await process_frame
	if controls.theme == null:
		return _fail_bool("touch controls must use the shared game theme")
	if controls.get_node("Jump").icon == null or controls.get_node("Action").icon == null:
		return _fail_bool("jump and action controls must have child-readable icons")
	for touch_target in [controls.get_node("Movement/Left"), controls.get_node("Movement/Right"), controls.get_node("Jump"), controls.get_node("Action")]:
		if minf(touch_target.size.x, touch_target.size.y) < 96.0:
			return _fail_bool("touch target %s must be at least 96 px at %s" % [touch_target.name, layout])
		if not _within(controls, touch_target):
			return _fail_bool("touch target %s must not overflow at %s" % [touch_target.name, layout])
	var screen_midpoint := layout.x * 0.5
	if controls.get_node("Movement/Left").get_global_rect().get_center().x >= screen_midpoint or controls.get_node("Movement/Right").get_global_rect().get_center().x >= screen_midpoint:
		return _fail_bool("movement controls must remain on the lower-left at %s" % layout)
	if controls.get_node("Jump").get_global_rect().get_center().x <= screen_midpoint or controls.get_node("Action").get_global_rect().get_center().x <= screen_midpoint:
		return _fail_bool("jump and action controls must remain on the lower-right at %s" % layout)
	root.remove_child(controls)
	controls.queue_free()
	return true


func _test_menu_actions_and_replacement() -> bool:
	var menu = load("res://ui/main_menu.tscn").instantiate()
	_prepare_layout(menu, Vector2(1024, 600))
	root.add_child(menu)
	await process_frame
	_created = 0
	_joined = 0
	_competition = 0
	menu.create_game.connect(_on_create_game)
	menu.join_game.connect(_on_join_game)
	menu.open_competition.connect(_on_open_competition)
	var choices: VBoxContainer = menu.get_node("Margin/VBox")
	var original_size := choices.size
	menu.get_node("Margin/VBox/Coop").emit_signal("pressed")
	await process_frame
	if menu.get_node_or_null("Margin/VBox/Create") == null or menu.get_node_or_null("Margin/VBox/Join") == null:
		return _fail_bool("cooperative choice must replace home choices with create/join")
	if menu.get_node_or_null("Margin/VBox/Competition") != null or choices.size.y > original_size.y + 1.0:
		return _fail_bool("cooperative choice must replace choices in place")
	menu.get_node("Margin/VBox/Create").emit_signal("pressed")
	var app_state = root.get_node("AppState")
	if app_state.selected_mode != "coop" or app_state.selected_level != "sunny_forest":
		return _fail_bool("create game must select the cooperative start mode")
	menu.get_node("Margin/VBox/Join").emit_signal("pressed")
	menu.get_node("Margin/VBox/Back").emit_signal("pressed")
	menu.get_node("Margin/VBox/Competition").emit_signal("pressed")
	await process_frame
	if _created != 1 or _joined != 1 or _competition != 1:
		return _fail_bool("menu must emit create, join, and competition signals")
	if app_state.selected_mode != "competition" or app_state.selected_level != "star_race":
		return _fail_bool("competition must select the competition start mode")
	if menu.get_node_or_null("Margin/VBox/Coop") == null:
		return _fail_bool("cooperative panel must provide a back path")
	root.remove_child(menu)
	menu.queue_free()
	return true


func _test_tutorial_animation() -> bool:
	var tutorial = load("res://ui/how_to_play.tscn").instantiate()
	_prepare_layout(tutorial, Vector2(1024, 600))
	root.add_child(tutorial)
	await process_frame
	if tutorial.layout_direction != Control.LAYOUT_DIRECTION_RTL or tutorial.get_node("Demo/Controls").layout_direction != Control.LAYOUT_DIRECTION_RTL:
		return _fail_bool("tutorial Hebrew containers must use RTL")
	var before: Vector2 = tutorial.get_node("Demo/Hero").position
	await create_timer(0.45).timeout
	var after: Vector2 = tutorial.get_node("Demo/Hero").position
	if before == after:
		return _fail_bool("tutorial animation must visibly change hero position over time")
	root.remove_child(tutorial)
	tutorial.queue_free()
	return true


func _test_tutorial_highlights() -> bool:
	var tutorial = load("res://ui/how_to_play.tscn").instantiate()
	_prepare_layout(tutorial, Vector2(1024, 600))
	root.add_child(tutorial)
	tutorial.advance_demo(0.0)
	var left: PanelContainer = tutorial.get_node("Demo/Controls/Left")
	var right: PanelContainer = tutorial.get_node("Demo/Controls/Right")
	var jump: PanelContainer = tutorial.get_node("Demo/Controls/Jump")
	var action: PanelContainer = tutorial.get_node("Demo/Controls/Action")
	var left_inactive := left.modulate
	var right_inactive := right.modulate
	var jump_inactive := jump.modulate
	var action_inactive := action.modulate
	tutorial.advance_demo(0.30)
	if right.modulate == right_inactive:
		return _fail_bool("tutorial right hint must visibly activate")
	tutorial.advance_demo(0.50)
	if jump.modulate == jump_inactive:
		return _fail_bool("tutorial jump hint must visibly activate")
	tutorial.advance_demo(0.65)
	if left.modulate == left_inactive:
		return _fail_bool("tutorial left hint must visibly activate")
	if action.modulate == action_inactive:
		return _fail_bool("tutorial action hint must visibly activate")
	root.remove_child(tutorial)
	tutorial.queue_free()
	return true


func _test_simultaneous_touch_and_keyboard() -> bool:
	var controls = load("res://ui/touch_controls.tscn").instantiate()
	_prepare_layout(controls, Vector2(1024, 600))
	root.add_child(controls)
	await process_frame
	controls._input(_screen_touch(0, controls.get_node("Movement/Right").get_global_rect().get_center(), true))
	controls._input(_screen_touch(1, controls.get_node("Jump").get_global_rect().get_center(), true))
	controls._input(_screen_touch(2, controls.get_node("Action").get_global_rect().get_center(), true))
	var frame = controls.input_frame()
	if frame.axis != 1.0 or not frame.jump or not frame.action:
		return _fail_bool("simultaneous pointers must support move + jump + action")
	controls._input(_screen_touch(1, Vector2.ZERO, false))
	frame = controls.input_frame()
	if frame.jump or frame.axis != 1.0 or not frame.action:
		return _fail_bool("releasing one pointer must preserve other active controls")
	controls._input(_screen_touch(0, Vector2.ZERO, false))
	controls._input(_screen_touch(2, Vector2.ZERO, false))
	controls._input(_screen_touch(3, controls.get_node("Action").get_global_rect().get_center(), true))
	var cancelled := _screen_touch(3, Vector2.ZERO, true)
	cancelled.canceled = true
	controls._input(cancelled)
	if controls.input_frame().action:
		return _fail_bool("cancelled pointers must clear their assigned action")
	var key := InputEventKey.new()
	key.keycode = KEY_A
	key.pressed = true
	controls._input(key)
	if controls.input_frame().axis >= 0.0:
		return _fail_bool("desktop keyboard mapping must remain available")
	key.pressed = false
	controls._input(key)
	root.remove_child(controls)
	controls.queue_free()
	return true


func _screen_touch(index: int, at_position: Vector2, pressed: bool) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = at_position
	event.pressed = pressed
	return event


func _on_create_game() -> void:
	_created += 1


func _on_join_game() -> void:
	_joined += 1


func _on_open_competition() -> void:
	_competition += 1


func _prepare_layout(control: Control, layout: Vector2) -> void:
	control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	control.position = Vector2.ZERO
	control.size = layout


func _within(parent: Control, child: Control) -> bool:
	return parent.get_global_rect().encloses(child.get_global_rect())


func _fail_bool(message: String) -> bool:
	_fail(message)
	return false


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
