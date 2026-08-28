extends SceneTree

## Verifies that the app actually holds together as a game: it boots to the
## Hebrew menu, every menu choice reaches a real screen, a finished level
## unlocks and offers the next one, and the player can always get back to the
## menu.

const SAVE_PATH := "user://animal-heroes-save.json"

# Autoload identifiers are not available to scripts run with -s, so the
# singletons are looked up on the tree instead.
var app_state: Node = null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	app_state = root.get_node("AppState")
	_clear_save()
	if not await _test_boots_to_menu():
		return
	if not await _test_menu_reaches_every_screen():
		return
	if not await _test_level_select_lists_unlocked_levels():
		return
	if not await _test_finished_level_unlocks_and_continues():
		return
	if not await _test_every_registered_scene_loads():
		return
	if not await _test_pause_returns_to_menu():
		return
	_clear_save()
	quit(0)


func _test_boots_to_menu() -> bool:
	var shell: Node = await _open_shell()
	if shell == null:
		return false
	var screen: Node = shell.current_screen()
	if screen == null or screen.scene_file_path != app_state.MENU_SCENE:
		return _fail_bool("the game must boot straight to the Hebrew main menu")
	if ProjectSettings.get_setting("application/run/main_scene") != "res://ui/game_shell.tscn":
		return _fail_bool("the shell must be the project main scene")
	_close_shell(shell)
	return true


func _test_menu_reaches_every_screen() -> bool:
	var shell: Node = await _open_shell()
	var menu: Node = shell.current_screen()

	# How to play and settings are opened directly.
	menu.get_node("Margin/VBox/HowTo").emit_signal("pressed")
	await process_frame
	if shell.current_screen().scene_file_path != app_state.scene_path_for(app_state.TUTORIAL_ID):
		return _fail_bool("the tutorial choice must open the tutorial screen")
	shell.current_screen().back_requested.emit()
	await process_frame
	if shell.current_screen().scene_file_path != app_state.MENU_SCENE:
		return _fail_bool("the tutorial must have a way back to the menu")

	shell.current_screen().get_node("Margin/VBox/Settings").emit_signal("pressed")
	await process_frame
	if shell.current_screen().scene_file_path != app_state.scene_path_for(app_state.SETTINGS_ID):
		return _fail_bool("the settings choice must open the settings screen")
	shell.current_screen().back_requested.emit()
	await process_frame

	# Cooperative hosting reaches the level picker.
	shell.current_screen().get_node("Margin/VBox/Coop").emit_signal("pressed")
	await process_frame
	shell.current_screen().get_node("Margin/VBox/Create").emit_signal("pressed")
	await process_frame
	if shell.current_screen().scene_file_path != "res://ui/level_select.tscn":
		return _fail_bool("hosting a cooperative game must open the level picker")
	if app_state.selected_mode != app_state.MODE_COOP:
		return _fail_bool("hosting a cooperative game must select the cooperative mode")

	# Competition reaches the same picker, listing the arenas.
	shell.show_menu()
	await process_frame
	shell.current_screen().get_node("Margin/VBox/Competition").emit_signal("pressed")
	await process_frame
	var picker: Node = shell.current_screen()
	if picker.scene_file_path != "res://ui/level_select.tscn":
		return _fail_bool("the competition choice must open the arena picker")
	if picker.level_count() != app_state.COMPETITION_ORDER.size():
		return _fail_bool("the arena picker must list every competition, got %d" % picker.level_count())
	_close_shell(shell)
	return true


func _test_level_select_lists_unlocked_levels() -> bool:
	_clear_save()
	var shell: Node = await _open_shell()
	shell.current_screen().get_node("Margin/VBox/Coop").emit_signal("pressed")
	await process_frame
	shell.current_screen().get_node("Margin/VBox/Create").emit_signal("pressed")
	await process_frame
	if shell.current_screen().level_count() != 1:
		return _fail_bool("a fresh save must offer only the first level, got %d" % shell.current_screen().level_count())

	app_state.unlock_levels(["crystal_caves"])
	shell.show_menu()
	await process_frame
	shell.current_screen().get_node("Margin/VBox/Coop").emit_signal("pressed")
	await process_frame
	shell.current_screen().get_node("Margin/VBox/Create").emit_signal("pressed")
	await process_frame
	if shell.current_screen().level_count() != 2:
		return _fail_bool("an unlocked level must appear in the picker, got %d" % shell.current_screen().level_count())
	_close_shell(shell)
	return true


func _test_finished_level_unlocks_and_continues() -> bool:
	_clear_save()
	var shell: Node = await _open_shell()
	var result := {
		"mode": "coop",
		"level_id": "sunny_forest",
		"next_level_id": "crystal_caves",
		"unlocked_levels": ["sunny_forest"],
		"campaign_completed": false,
		"winner_peer_id": 0,
		"scores": {},
	}
	shell._on_level_finished(result)
	await process_frame
	if not app_state.is_unlocked("crystal_caves"):
		return _fail_bool("finishing a level must unlock the next one")
	var results_screen: Node = shell.current_screen()
	if results_screen.scene_file_path != app_state.RESULTS_SCENE:
		return _fail_bool("finishing a level must open the results screen")
	if not results_screen.next_button.visible:
		return _fail_bool("results must offer the next level when there is one")

	# A finished competition has no next level to offer.
	shell._on_level_finished({"mode": "competition", "level_id": "star_race", "winner_peer_id": 1, "scores": {1: 5, 2: 3}})
	await process_frame
	if shell.current_screen().next_button.visible:
		return _fail_bool("a competition result must not offer a campaign level")
	if shell.current_screen().displayed_scores.size() != 2:
		return _fail_bool("a competition result must show both scores")

	shell.current_screen().return_to_menu.emit()
	await process_frame
	if shell.current_screen().scene_file_path != app_state.MENU_SCENE:
		return _fail_bool("results must lead back to the menu")
	_close_shell(shell)
	return true


func _test_every_registered_scene_loads() -> bool:
	for level_id in app_state.SCENES:
		var path: String = app_state.SCENES[level_id]
		if not ResourceLoader.exists(path):
			return _fail_bool("%s points at a missing scene: %s" % [level_id, path])
		if load(path) == null:
			return _fail_bool("%s does not load: %s" % [level_id, path])
		if app_state.is_campaign_level(level_id) and app_state.title_for(level_id).is_empty():
			return _fail_bool("%s needs a Hebrew title for the level picker" % level_id)
	return true


func _test_pause_returns_to_menu() -> bool:
	var shell: Node = await _open_shell()
	var level = load(app_state.scene_path_for("test_arena")).instantiate()
	shell.get_node("Screen").add_child(level)
	await process_frame
	level.exit_requested.connect(shell._on_level_exit_requested)
	level.touch_controls.get_node("Pause").emit_signal("pressed")
	await process_frame
	if not shell.pause_overlay.visible:
		return _fail_bool("the in-level pause button must open the pause overlay")
	shell.pause_overlay.resume_requested.emit()
	if shell.pause_overlay.visible:
		return _fail_bool("resuming must close the pause overlay")
	shell.pause_overlay.open()
	shell.pause_overlay.exit_requested.emit()
	await process_frame
	if shell.current_screen().scene_file_path != app_state.MENU_SCENE:
		return _fail_bool("leaving a level must return to the menu")
	level.queue_free()
	_close_shell(shell)
	return true


func _open_shell() -> Node:
	var scene: PackedScene = load("res://ui/game_shell.tscn")
	if scene == null:
		_fail("the game shell scene must exist")
		return null
	var shell: Node = scene.instantiate()
	root.add_child(shell)
	await process_frame
	return shell


func _close_shell(shell: Node) -> void:
	root.remove_child(shell)
	shell.queue_free()


func _clear_save() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func _fail_bool(message: String) -> bool:
	_fail(message)
	return false


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
