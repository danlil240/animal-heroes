extends Node

## The running game. This is the only place that swaps screens.
##
## Screens and levels never load each other; they report intent through their
## own signals or AppState, and the shell decides what to show next. The LAN
## handshake also lives here: the hosting tablet picks the level and announces
## it, the joining tablet discovers the host and follows whatever the host
## announced.

const HOST_CHARACTER := "rabbit"
const GUEST_CHARACTER := "fox"

const DiscoveryServiceScript := preload("res://network/discovery_service.gd")

@onready var screen_host: Node = $Screen
@onready var connection_overlay: Control = $Overlay/ConnectionOverlay
@onready var pause_overlay: Control = $Overlay/PauseOverlay

var _discovery: DiscoveryService = null
var _current_screen: Node = null
var _is_hosting: bool = false


func _ready() -> void:
	_discovery = DiscoveryServiceScript.new()
	_discovery.name = "Discovery"
	add_child(_discovery)
	_discovery.host_found.connect(_on_host_found)
	_discovery.incompatible_host_found.connect(_on_incompatible_host_found)
	AppState.mode_started.connect(_on_mode_started)
	AppState.results_requested.connect(_on_results_requested)
	AppState.menu_requested.connect(_on_menu_requested)
	Session.peer_ready.connect(_on_peer_ready)
	Session.level_start_received.connect(_on_level_start_received)
	Session.session_error.connect(_on_session_error)
	pause_overlay.resume_requested.connect(_on_resume_requested)
	pause_overlay.exit_requested.connect(_on_menu_requested)
	show_menu()


func show_menu() -> void:
	_leave_session()
	AudioDirector.play_menu_music()
	_show_scene(AppState.MENU_SCENE)


## The screen currently on display, for tests and for the shell's own wiring.
func current_screen() -> Node:
	return _current_screen


func _on_mode_started(mode_id: String, level_id: String) -> void:
	if mode_id == AppState.MODE_TUTORIAL or mode_id == AppState.MODE_SETTINGS:
		_show_scene(AppState.scene_path_for(level_id))
		return
	_host_level(level_id)


## Opens the level picker for the tablet that will host.
func _on_create_game() -> void:
	_is_hosting = true
	var screen := _show_scene("res://ui/level_select.tscn")
	var level_ids: Array = AppState.unlocked_levels() if AppState.selected_mode == AppState.MODE_COOP else AppState.COMPETITION_ORDER
	var heading := "בוחרים הרפתקה" if AppState.selected_mode == AppState.MODE_COOP else "בוחרים תחרות"
	screen.show_levels(level_ids, heading)


## Starts looking for the other tablet's game; the host chooses the level.
func _on_join_game() -> void:
	_is_hosting = false
	Session.selected_character = GUEST_CHARACTER
	Session.begin_discovery()
	_discovery.listen()
	connection_overlay.show_state(Session.state)


func _host_level(level_id: String) -> void:
	_is_hosting = true
	Session.selected_character = HOST_CHARACTER
	if Session.create_game() != OK:
		return
	_discovery.host(Session.session_id)
	connection_overlay.show_state(Session.state)


func _on_host_found(info: Dictionary) -> void:
	if _is_hosting or Session.state != Session.DISCOVERING:
		return
	Session.join_game(String(info.get("host", "")), int(info.get("port", 0)), GUEST_CHARACTER)


func _on_incompatible_host_found(info: Dictionary) -> void:
	if _is_hosting or Session.state != Session.DISCOVERING:
		return
	var protocol = preload("res://network/protocol.gd")
	var comparison := protocol.compare_builds(protocol.local_build_descriptor(), info.get("build", {}))
	connection_overlay.show_incompatibility(String(comparison.get("relation", "unknown")))


## Both tablets are in the session, so the host announces the chosen level.
func _on_peer_ready(_peer_id: int, _character_id: String) -> void:
	if _is_hosting:
		Session.start_level(AppState.selected_level)


func _on_level_start_received(level_id: String) -> void:
	connection_overlay.hide()
	var level := _show_scene(AppState.scene_path_for(level_id))
	if level == null:
		return
	level.configure_local_role(Session.selected_character)
	level.level_finished.connect(_on_level_finished)
	level.exit_requested.connect(_on_level_exit_requested)
	AudioDirector.play_level_music(level_id)


func _on_level_finished(result: Dictionary) -> void:
	AppState.record_result(result)
	AppState.open_results(result)


func _on_results_requested(result: Dictionary) -> void:
	var screen := _show_scene(AppState.RESULTS_SCENE)
	screen.show_result(result)
	screen.rematch_requested.connect(_on_rematch_requested)
	screen.next_level_requested.connect(_on_next_level_requested)
	screen.return_to_menu.connect(_on_menu_requested)


func _on_rematch_requested() -> void:
	if _is_hosting:
		Session.start_level(AppState.selected_level)


func _on_next_level_requested() -> void:
	var next_level_id := String(AppState.last_result.get("next_level_id", ""))
	if next_level_id.is_empty():
		_on_menu_requested()
		return
	AppState.select_mode(AppState.selected_mode, next_level_id)
	if _is_hosting:
		Session.start_level(next_level_id)


func _on_level_exit_requested() -> void:
	pause_overlay.open()


func _on_resume_requested() -> void:
	pause_overlay.close()


func _on_menu_requested() -> void:
	show_menu()


func _on_session_error(message: String) -> void:
	_leave_session()
	_show_connection_error(message)
	if not (_current_screen is Control) or _current_screen.scene_file_path != AppState.MENU_SCENE:
		_show_scene(AppState.MENU_SCENE)


func _show_connection_error(message: String) -> void:
	connection_overlay.get_node("Panel/Status").text = message
	connection_overlay.get_node("Panel/ManualIp").visible = false
	connection_overlay.show()


func _leave_session() -> void:
	_is_hosting = false
	_discovery.stop()
	Session.leave_game()
	connection_overlay.hide()
	pause_overlay.close()


func _show_scene(path: String) -> Node:
	if path.is_empty():
		push_error("no scene registered for the requested screen")
		return null
	var scene: PackedScene = load(path)
	if scene == null:
		push_error("could not load screen: " + path)
		return null
	if _current_screen != null:
		screen_host.remove_child(_current_screen)
		_current_screen.queue_free()
	_current_screen = scene.instantiate()
	screen_host.add_child(_current_screen)
	_wire_menu(_current_screen)
	return _current_screen


func _wire_menu(screen: Node) -> void:
	if screen.has_signal("create_game"):
		screen.create_game.connect(_on_create_game)
	if screen.has_signal("join_game"):
		screen.join_game.connect(_on_join_game)
	if screen.has_signal("open_competition"):
		screen.open_competition.connect(_on_create_game)
	if screen.has_signal("level_chosen"):
		screen.level_chosen.connect(_on_level_chosen)
	if screen.has_signal("join_requested"):
		screen.join_requested.connect(_on_join_game)
	if screen.has_signal("back_requested"):
		screen.back_requested.connect(_on_menu_requested)


func _on_level_chosen(level_id: String) -> void:
	AppState.start_mode(AppState.selected_mode, level_id)
