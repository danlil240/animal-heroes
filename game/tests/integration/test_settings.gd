extends SceneTree

# Tests audio settings persistence and bus structure.
# Verifies that music/SFX volumes and vibration setting persist through
# save/load round-trips and that the AudioDirector converts linear volume
# to dB correctly.

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var SaveStoreScript: Script = load("res://autoload/save_store.gd")
	var AudioDirectorScript: Script = load("res://audio/audio_director.gd")
	if AudioDirectorScript == null:
		_fail("audio_director must exist")
		return
	var save_store: Node = SaveStoreScript.new()
	var director: Node = AudioDirectorScript.new()
	director._setup_buses()

	# Test bus existence
	if AudioServer.get_bus_index("Music") == -1:
		_fail("Music bus must exist")
		return
	if AudioServer.get_bus_index("SFX") == -1:
		_fail("SFX bus must exist")
		return

	# Test linear-to-dB conversion
	var db_zero: float = director.linear_to_db(1.0)
	if absf(db_zero) > 0.01:
		_fail("linear 1.0 must convert to 0 dB, got %f" % db_zero)
		return
	var db_half: float = director.linear_to_db(0.5)
	if absf(db_half - (-6.02)) > 0.1:
		_fail("linear 0.5 must convert to ~-6 dB, got %f" % db_half)
		return

	# Test settings round-trip
	var path := "user://test-audio-settings.json"
	var data := {
		"version": 1,
		"unlocked_levels": ["sunny_forest"],
		"music": 0.25,
		"sfx": 0.75,
		"vibration": false,
	}
	if save_store.save_data(data, path) != OK:
		_fail("save must succeed")
		return
	var loaded: Dictionary = save_store.load_data(path)
	if loaded.get("music") != 0.25 or loaded.get("sfx") != 0.75 or loaded.get("vibration") != false:
		_fail("settings must round-trip: %s" % str(loaded))
		return

	# Test applying settings to buses
	director.apply_settings(loaded)
	var music_db: float = AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))
	var sfx_db: float = AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX"))
	var expected_music_db: float = director.linear_to_db(0.25)
	var expected_sfx_db: float = director.linear_to_db(0.75)
	if absf(music_db - expected_music_db) > 0.1:
		_fail("music bus volume must match setting: got %f, expected %f" % [music_db, expected_music_db])
		return
	if absf(sfx_db - expected_sfx_db) > 0.1:
		_fail("sfx bus volume must match setting: got %f, expected %f" % [sfx_db, expected_sfx_db])
		return

	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
