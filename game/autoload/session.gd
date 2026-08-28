extends Node


signal state_changed(next_state: String)
signal peer_ready(peer_id: int, character_id: String)
signal session_error(message: String)

const GameConfig = preload("res://core/game_config.gd")
const SessionState = preload("res://network/session_state.gd")

const IDLE := SessionState.IDLE
const DISCOVERING := SessionState.DISCOVERING
const CONNECTING := SessionState.CONNECTING
const LOBBY := SessionState.LOBBY
const PLAYING := SessionState.PLAYING
const RECONNECTING := SessionState.RECONNECTING

var state := IDLE
var selected_character := "rabbit"
var _peer: ENetMultiplayerPeer
var _is_host := false
var _characters_by_peer: Dictionary = {}


func create_game() -> Error:
	leave_game()
	_peer = ENetMultiplayerPeer.new()
	var result := _peer.create_server(GameConfig.GAME_PORT, GameConfig.MAX_PLAYERS - 1)
	if result != OK:
		_peer = null
		_fail("לא ניתן ליצור משחק מקומי")
		return result
	_is_host = true
	multiplayer.multiplayer_peer = _peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_characters_by_peer[1] = selected_character
	_set_state(LOBBY)
	return OK


func join_game(host: String, port: int = GameConfig.GAME_PORT, character_id: String = "fox") -> Error:
	if not host.is_valid_ip_address() or port <= 0 or port > 65535:
		return ERR_INVALID_PARAMETER
	leave_game()
	selected_character = character_id
	_peer = ENetMultiplayerPeer.new()
	var result := _peer.create_client(host, port)
	if result != OK:
		_peer = null
		_fail("לא ניתן להתחבר למשחק")
		return result
	_is_host = false
	multiplayer.multiplayer_peer = _peer
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_set_state(CONNECTING)
	return OK


func leave_game() -> void:
	if multiplayer.multiplayer_peer == _peer:
		multiplayer.multiplayer_peer = null
	if _peer != null:
		_peer.close()
	_peer = null
	_is_host = false
	_characters_by_peer.clear()
	if state != IDLE:
		_set_state(IDLE)


func _on_peer_connected(peer_id: int) -> void:
	if not _is_host or _characters_by_peer.size() >= GameConfig.MAX_PLAYERS:
		_peer.disconnect_peer(peer_id, true)



func _on_peer_disconnected(peer_id: int) -> void:
	_characters_by_peer.erase(peer_id)
	if _is_host and state == PLAYING:
		_set_state(LOBBY)


func _on_connected_to_server() -> void:
	_set_state(LOBBY)
	request_lobby_entry.rpc(GameConfig.PROTOCOL_VERSION, GameConfig.CONTENT_VERSION, selected_character)


func _on_connection_failed() -> void:
	_fail("החיבור נכשל")
	leave_game()


func _on_server_disconnected() -> void:
	_fail("החיבור נותק")
	leave_game()


func _set_state(next_state: String) -> void:
	if state == next_state:
		return
	if not SessionState.is_valid_transition(state, next_state):
		return
	state = next_state
	state_changed.emit(state)


func _fail(message: String) -> void:
	session_error.emit(message)


@rpc("any_peer", "reliable")
func request_lobby_entry(protocol_version: int, content_version: String, requested_character: String) -> void:
	if not _is_host:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if protocol_version != GameConfig.PROTOCOL_VERSION or content_version != GameConfig.CONTENT_VERSION:
		reject_lobby_entry.rpc_id(peer_id, "גרסת המשחק אינה תואמת")
		_peer.disconnect_peer(peer_id)
		return
	if requested_character != "rabbit" and requested_character != "fox":
		reject_lobby_entry.rpc_id(peer_id, "הדמות שנבחרה אינה זמינה")
		_peer.disconnect_peer(peer_id)
		return
	var character_id := requested_character if not _characters_by_peer.values().has(requested_character) else _other_character(requested_character)
	if _characters_by_peer.values().has(character_id):
		reject_lobby_entry.rpc_id(peer_id, "המשחק מלא")
		_peer.disconnect_peer(peer_id)
		return
	_characters_by_peer[peer_id] = character_id
	confirm_lobby_entry.rpc_id(peer_id, character_id)
	peer_ready.emit(peer_id, character_id)
	_set_state(PLAYING)


@rpc("authority", "reliable")
func confirm_lobby_entry(character_id: String) -> void:
	selected_character = character_id
	peer_ready.emit(multiplayer.get_unique_id(), character_id)
	_set_state(PLAYING)


@rpc("authority", "reliable")
func reject_lobby_entry(message: String) -> void:
	_fail(message)
	leave_game()


func _other_character(character_id: String) -> String:
	return "fox" if character_id == "rabbit" else "rabbit"
