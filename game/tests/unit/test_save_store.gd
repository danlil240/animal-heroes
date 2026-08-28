extends SceneTree

const DEFAULT_DATA := {
	"version": 1,
	"unlocked_levels": ["sunny_forest"],
	"music": 0.8,
	"sfx": 0.8,
	"vibration": true,
}

class FailingPromotionStore extends "res://autoload/save_store.gd":
	func _rename_absolute(from_path: String, to_path: String) -> Error:
		if from_path.ends_with(".tmp"):
			return ERR_CANT_CREATE
		return DirAccess.rename_absolute(from_path, to_path)

func _init() -> void:
	var save_store_script: Script = load("res://autoload/save_store.gd")
	if save_store_script == null:
		push_error("SaveStore script is missing")
		quit(1)
		return

	var store: Node = save_store_script.new()
	var passed := _test_round_trip(store) and _test_missing_save_uses_defaults(store) and _test_unsupported_version_uses_defaults(store) and _test_fractional_version_uses_defaults(store) and _test_failed_promotion_preserves_existing_save(store) and _test_start_mode_selects_requested_mode_and_level() and _test_autoloads_are_registered()
	store.free()
	if not passed:
		quit(1)
		return
	quit(0)

func _test_round_trip(store: Node) -> bool:
	var path := "user://test-save-store-round-trip.json"
	var data := {"version": 1, "unlocked_levels": ["sunny_forest"], "music": 0.6, "sfx": 0.8, "vibration": false}
	var result: Error = store.save_data(data, path)
	var loaded: Dictionary = store.load_data(path)
	_cleanup(path)
	if result != OK or loaded != data or typeof(loaded.get("version")) != TYPE_INT:
		push_error("save round trip failed")
		return false
	return true

func _test_missing_save_uses_defaults(store: Node) -> bool:
	var path := "user://test-save-store-missing.json"
	_cleanup(path)
	if store.load_data(path) != DEFAULT_DATA:
		push_error("missing save did not return defaults")
		return false
	return true

func _test_unsupported_version_uses_defaults(store: Node) -> bool:
	var path := "user://test-save-store-unsupported.json"
	var result: Error = store.save_data({"version": 2}, path)
	var loaded: Dictionary = store.load_data(path)
	_cleanup(path)
	if result != OK or loaded != DEFAULT_DATA:
		push_error("unsupported save version did not return defaults")
		return false
	return true

func _test_fractional_version_uses_defaults(store: Node) -> bool:
	var path := "user://test-save-store-fractional-version.json"
	var result: Error = store.save_data({"version": 1.5}, path)
	var loaded: Dictionary = store.load_data(path)
	_cleanup(path)
	if result != OK or loaded != DEFAULT_DATA:
		push_error("fractional save version did not return defaults")
		return false
	return true

func _test_failed_promotion_preserves_existing_save(store: Node) -> bool:
	var path := "user://test-save-store-failed-promotion.json"
	var original := {"version": 1, "unlocked_levels": ["sunny_forest"], "music": 0.4, "sfx": 0.5, "vibration": true}
	var replacement := {"version": 1, "unlocked_levels": ["sunny_forest", "river_crossing"], "music": 0.1, "sfx": 0.2, "vibration": false}
	var initial_result: Error = store.save_data(original, path)
	var failing_store := FailingPromotionStore.new()
	var save_result: Error = failing_store.save_data(replacement, path)
	failing_store.free()
	var loaded: Dictionary = store.load_data(path)
	_cleanup(path)
	if initial_result != OK or save_result == OK or loaded != original:
		push_error("failed promotion did not preserve existing save")
		return false
	return true

func _test_start_mode_selects_requested_mode_and_level() -> bool:
	var app_state_script: Script = load("res://autoload/app_state.gd")
	if app_state_script == null:
		push_error("AppState script is missing")
		return false
	var state: Node = app_state_script.new()
	state.start_mode("cooperative", "sunny_forest")
	var selected_mode: Variant = state.get("selected_mode")
	var selected_level: Variant = state.get("selected_level")
	state.free()
	if selected_mode != "cooperative" or selected_level != "sunny_forest":
		push_error("start_mode did not select the requested mode and level")
		return false
	return true

func _test_autoloads_are_registered() -> bool:
	var save_store_path: Variant = ProjectSettings.get_setting("autoload/SaveStore", "")
	var app_state_path: Variant = ProjectSettings.get_setting("autoload/AppState", "")
	var session_path: Variant = ProjectSettings.get_setting("autoload/Session", "")
	if save_store_path != "*res://autoload/save_store.gd" or app_state_path != "*res://autoload/app_state.gd" or session_path != "*res://autoload/session.gd":
		push_error("SaveStore, AppState, and Session autoloads are not registered")
		return false
	return true

func _cleanup(path: String) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".tmp"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".bak"))
