extends Node

const DEFAULT_PATH := "user://animal-heroes-save.json"
const CURRENT_VERSION := 1
const DEFAULT_DATA := {
	"version": CURRENT_VERSION,
	"unlocked_levels": ["sunny_forest"],
	"music": 0.8,
	"sfx": 0.8,
	"vibration": true,
}

func save_data(data: Dictionary, path_override: String = "") -> Error:
	var path := path_override if not path_override.is_empty() else DEFAULT_PATH
	var temp_path := path + ".tmp"
	var backup_path := path + ".bak"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data))
	file.close()
	var absolute_path := ProjectSettings.globalize_path(path)
	var absolute_temp_path := ProjectSettings.globalize_path(temp_path)
	var absolute_backup_path := ProjectSettings.globalize_path(backup_path)
	if not FileAccess.file_exists(path):
		var new_save_result := _rename_absolute(absolute_temp_path, absolute_path)
		if new_save_result != OK:
			DirAccess.remove_absolute(absolute_temp_path)
		return new_save_result

	if FileAccess.file_exists(backup_path):
		var remove_backup_result := DirAccess.remove_absolute(absolute_backup_path)
		if remove_backup_result != OK:
			DirAccess.remove_absolute(absolute_temp_path)
			return remove_backup_result
	var backup_result := _rename_absolute(absolute_path, absolute_backup_path)
	if backup_result != OK:
		DirAccess.remove_absolute(absolute_temp_path)
		return backup_result
	var promotion_result := _rename_absolute(absolute_temp_path, absolute_path)
	if promotion_result == OK:
		DirAccess.remove_absolute(absolute_backup_path)
		return OK

	var restore_result := _rename_absolute(absolute_backup_path, absolute_path)
	DirAccess.remove_absolute(absolute_temp_path)
	if restore_result != OK:
		return restore_result
	return promotion_result

func load_data(path_override: String = "") -> Dictionary:
	var path := path_override if not path_override.is_empty() else DEFAULT_PATH
	if not FileAccess.file_exists(path):
		return _default_data()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary and _has_current_version(parsed):
		var normalized: Dictionary = parsed.duplicate(true)
		normalized["version"] = CURRENT_VERSION
		return normalized
	return _default_data()

func _has_current_version(data: Dictionary) -> bool:
	var version: Variant = data.get("version")
	return (typeof(version) == TYPE_INT or typeof(version) == TYPE_FLOAT) and int(version) == CURRENT_VERSION

func _default_data() -> Dictionary:
	return DEFAULT_DATA.duplicate(true)

func _rename_absolute(from_path: String, to_path: String) -> Error:
	return DirAccess.rename_absolute(from_path, to_path)
