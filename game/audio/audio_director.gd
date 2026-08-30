extends Node

# Routes music and SFX through independent buses, applies persisted settings,
# and provides visual event signals for audio-only events.
#
# Buses: Master (0) -> Music (1) -> SFX (2)
# Settings are loaded from SaveStore and applied on _ready.

const MAX_SFX_VOICES: int = 12
const MAX_PROJECTILE_VOICES: int = 4
const MUSIC_CROSSFADE_TIME: float = 0.5

const MUSIC_SUNNY_FOREST := "res://assets/audio/sunny_forest.wav"
const MUSIC_CRYSTAL_CAVES := "res://assets/audio/crystal_caves.wav"
const MUSIC_CLOUD_FACTORY := "res://assets/audio/cloud_factory.wav"
const MUSIC_COMPETITION := "res://assets/audio/competition.wav"
const SFX_UI := "res://assets/audio/sfx_ui.wav"
const SFX_GAMEPLAY := "res://assets/audio/sfx_gameplay.wav"

const BUS_MASTER := "Master"
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"

signal checkpoint_activated(checkpoint_id: String)
signal damage_taken(peer_id: int)
signal objective_completed(objective_id: String)
signal connection_state_changed(state: String)

var _music_player: AudioStreamPlayer
var _sfx_players: Array[AudioStreamPlayer] = []
var _projectile_voices_in_use: int = 0
var _current_music_path: String = ""


func _ready() -> void:
	_setup_buses()
	_setup_players()
	var SaveStoreScript: Script = load("res://autoload/save_store.gd")
	var save_store: Node = SaveStoreScript.new()
	var data: Dictionary = save_store.load_data()
	apply_settings(data)


func _setup_buses() -> void:
	# Master bus (index 0) always exists.
	# Create Music and SFX buses if they don't exist.
	if AudioServer.get_bus_index(BUS_MUSIC) == -1:
		AudioServer.add_bus(AudioServer.get_bus_count())
		AudioServer.set_bus_name(AudioServer.get_bus_count() - 1, BUS_MUSIC)
		AudioServer.set_bus_send(AudioServer.get_bus_count() - 1, BUS_MASTER)
	if AudioServer.get_bus_index(BUS_SFX) == -1:
		AudioServer.add_bus(AudioServer.get_bus_count())
		AudioServer.set_bus_name(AudioServer.get_bus_count() - 1, BUS_SFX)
		AudioServer.set_bus_send(AudioServer.get_bus_count() - 1, BUS_MASTER)


func _setup_players() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = BUS_MUSIC
	add_child(_music_player)
	for i in MAX_SFX_VOICES:
		var player := AudioStreamPlayer.new()
		player.bus = BUS_SFX
		add_child(player)
		_sfx_players.append(player)


func apply_settings(data: Dictionary) -> void:
	var music_volume: float = float(data.get("music", 0.8))
	var sfx_volume: float = float(data.get("sfx", 0.8))
	var music_idx := AudioServer.get_bus_index(BUS_MUSIC)
	var sfx_idx := AudioServer.get_bus_index(BUS_SFX)
	if music_idx != -1:
		AudioServer.set_bus_volume_db(music_idx, linear_to_db(music_volume))
	if sfx_idx != -1:
		AudioServer.set_bus_volume_db(sfx_idx, linear_to_db(sfx_volume))


func linear_to_db(linear: float) -> float:
	var clamped: float = clampf(linear, 0.0, 1.0)
	if clamped <= 0.0001:
		return -80.0
	return 20.0 * log(clamped) / log(10.0)


func play_music(path: String) -> void:
	if path == _current_music_path and _music_player.playing:
		return
	_current_music_path = path
	if not ResourceLoader.exists(path):
		return
	var stream := load(path)
	if stream == null:
		return
	_music_player.stream = stream
	_music_player.play()


func play_sfx(path: String, is_projectile: bool = false) -> void:
	if is_projectile and _projectile_voices_in_use >= MAX_PROJECTILE_VOICES:
		return
	if is_projectile:
		_projectile_voices_in_use += 1
	var player := _find_available_sfx_player()
	if player == null:
		if is_projectile:
			_projectile_voices_in_use -= 1
		return
	if not ResourceLoader.exists(path):
		if is_projectile:
			_projectile_voices_in_use -= 1
		return
	player.stream = load(path)
	player.play()
	if is_projectile:
		if player.finished.is_connected(_on_projectile_voice_finished):
			player.finished.disconnect(_on_projectile_voice_finished)
			_projectile_voices_in_use = maxi(_projectile_voices_in_use - 1, 0)
		player.finished.connect(_on_projectile_voice_finished, CONNECT_ONE_SHOT)


## World music per level, so each screen sounds like where the players are.
const LEVEL_MUSIC := {
	"sunny_forest": MUSIC_SUNNY_FOREST,
	"crystal_caves": MUSIC_CRYSTAL_CAVES,
	"cloud_factory": MUSIC_CLOUD_FACTORY,
	"robot_boss": MUSIC_CLOUD_FACTORY,
	"star_race": MUSIC_COMPETITION,
	"treasure_dash": MUSIC_COMPETITION,
	"bubble_bounce": MUSIC_COMPETITION,
	"test_arena": MUSIC_SUNNY_FOREST,
}

const GAMEPLAY_CUES := {
	"star": false,
	"enemy": false,
	"shot": true,
	"enemy_hit": false,
	"enemy_defeat": false,
	"spring": false,
	"combo": false,
	"secret": false,
	"teamwork": false,
	"damage": false,
	"checkpoint": false,
	"bubble": true,
	"finish": false,
}


func play_gameplay_cue(cue: String, _peer_id: int = 0) -> bool:
	if not GAMEPLAY_CUES.has(cue):
		return false
	play_sfx(SFX_GAMEPLAY, bool(GAMEPLAY_CUES[cue]))
	return true


func play_level_music(level_id: String) -> void:
	play_music(LEVEL_MUSIC.get(level_id, MUSIC_SUNNY_FOREST))


func play_menu_music() -> void:
	play_music(MUSIC_SUNNY_FOREST)


func play_ui_sound() -> void:
	play_sfx(SFX_UI)


func play_gameplay_sound() -> void:
	play_sfx(SFX_GAMEPLAY)


func _find_available_sfx_player() -> AudioStreamPlayer:
	for player in _sfx_players:
		if not player.playing:
			return player
	return null


func _on_projectile_voice_finished() -> void:
	_projectile_voices_in_use = maxi(_projectile_voices_in_use - 1, 0)


func emit_checkpoint_activated(checkpoint_id: String) -> void:
	checkpoint_activated.emit(checkpoint_id)


func emit_damage_taken(peer_id: int) -> void:
	damage_taken.emit(peer_id)


func emit_objective_completed(objective_id: String) -> void:
	objective_completed.emit(objective_id)


func emit_connection_state_changed(state: String) -> void:
	connection_state_changed.emit(state)
