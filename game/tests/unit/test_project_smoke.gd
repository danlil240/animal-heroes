extends SceneTree

func _init() -> void:
	var config := load("res://core/game_config.gd")
	var build_info := load("res://core/build_info.gd")
	if build_info == null or build_info.current() != {
		"version_name": "1.0.0-dev.1",
		"version_code": 1,
		"application_protocol_version": 1,
		"save_schema_version": 1,
	}:
		push_error("build_info contract missing")
		quit(1)
		return
	if config == null or config.PROTOCOL_VERSION != build_info.APPLICATION_PROTOCOL_VERSION or config.CONTENT_VERSION != build_info.VERSION_NAME or config.UPDATE_DISCOVERY_PORT != 28742:
		push_error("game_config contract missing")
		quit(1)
		return
	var icon_path := String(ProjectSettings.get_setting("application/config/icon", ""))
	if icon_path.is_empty() or not ResourceLoader.exists(icon_path):
		push_error("the Android release must configure a loadable application icon")
		quit(1)
		return
	quit(0)
