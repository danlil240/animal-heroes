extends SceneTree

func _init() -> void:
	var config := load("res://core/game_config.gd")
	if config == null or config.PROTOCOL_VERSION != 1 or config.CONTENT_VERSION != "1.0.0":
		push_error("game_config contract missing")
		quit(1)
		return
	var icon_path := String(ProjectSettings.get_setting("application/config/icon", ""))
	if icon_path.is_empty() or not ResourceLoader.exists(icon_path):
		push_error("the Android release must configure a loadable application icon")
		quit(1)
		return
	quit(0)
