extends Node


signal state_changed(next_state: String)
signal peer_ready(peer_id: int, character_id: String)
signal session_error(message: String)
signal paused()
signal resumed()
signal snapshot_received(snapshot: Dictionary)
signal reconnect_state_changed(next_state: String)
signal checkpoint_confirmed(checkpoint: Dictionary)
signal level_start_received(level_id: String)
signal level_start_acknowledged(peer_id: int, level_id: String)

const GameConfig = preload("res://core/game_config.gd")
const SessionState = preload("res://network/session_state.gd")
const ReconnectController = preload("res://network/reconnect_controller.gd")
const Protocol = preload("res://network/protocol.gd")
const CheckpointState = preload("res://core/checkpoint_state.gd")

const IDLE := SessionState.IDLE
const DISCOVERING := SessionState.DISCOVERING
const CONNECTING := SessionState.CONNECTING
const LOBBY := SessionState.LOBBY
const PLAYING := SessionState.PLAYING
const RECONNECTING := SessionState.RECONNECTING

## Both tablets reach each other over IPv4 on the Wi-Fi LAN, and that is what
## discovery advertises. Binding the IPv4 wildcard instead of ENet's default
## IPv6 wildcard keeps those advertised addresses connectable.
const BIND_ADDRESS := "0.0.0.0"

const TRAFFIC_TIMEOUT: float = 1.5
const RESUME_COUNTDOWN: float = 3.0
const SESSION_ID_ALPHABET := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

var state := IDLE
var selected_character := "rabbit"
var session_id := ""
var current_level_id := ""
var confirmed_checkpoint: Dictionary = {}

var _peer: ENetMultiplayerPeer
var _is_host := false
var _characters_by_peer: Dictionary = {}
var _reconnect := ReconnectController.new()
var _traffic_timer: float = 0.0
var _paused: bool = false
var _resume_acks: Dictionary = {}
var _authoritative_snapshot: Dictionary = {}
var _resume_countdown_remaining: float = 0.0
var _last_host := ""
var _last_port: int = GameConfig.GAME_PORT
var _last_character := "fox"
var _retry_in_flight: bool = false


func _ready() -> void:
	_reconnect.state_changed.connect(_on_reconnect_state_changed)
	_reconnect.retry_scheduled.connect(_on_retry_scheduled)
	_reconnect.failed.connect(_on_reconnect_failed)


func _process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	var step := maxf(delta, 0.0)
	if state == PLAYING and not _paused:
		_traffic_timer += step
		if _traffic_timer >= TRAFFIC_TIMEOUT:
			_begin_reconnect()
	if _reconnect.state == ReconnectController.RETRYING:
		_reconnect.tick(step)
	if _resume_countdown_remaining > 0.0:
		_resume_countdown_remaining -= step
		if _resume_countdown_remaining <= 0.0:
			_complete_resume()


func create_game() -> Error:
	leave_game()
	_peer = ENetMultiplayerPeer.new()
	_peer.set_bind_ip(BIND_ADDRESS)
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
	session_id = _generate_session_id()
	_set_state(LOBBY)
	return OK


## Starts looking for a host on the local network.
func begin_discovery() -> void:
	_set_state(DISCOVERING)


## Host-only: tells both peers which level to open, so the joining tablet never
## has to guess what the host picked.
func start_level(level_id: String) -> void:
	if level_id.is_empty():
		return
	if not _is_host and _peer != null:
		return
	current_level_id = level_id
	if _is_host and _peer != null:
		deliver_level_start.rpc(level_id)
	level_start_received.emit(level_id)


@rpc("authority", "reliable")
func deliver_level_start(level_id: String) -> void:
	if level_id.is_empty():
		return
	current_level_id = level_id
	level_start_received.emit(level_id)
	if not _is_host and _peer != null:
		acknowledge_level_start.rpc_id(1, level_id)


@rpc("any_peer", "reliable")
func acknowledge_level_start(level_id: String) -> void:
	if not _is_host or level_id != current_level_id:
		return
	level_start_acknowledged.emit(multiplayer.get_remote_sender_id(), level_id)


func join_game(host: String, port: int = GameConfig.GAME_PORT, character_id: String = "fox") -> Error:
	if not host.is_valid_ip_address() or port <= 0 or port > 65535:
		return ERR_INVALID_PARAMETER
	if not _retry_in_flight:
		leave_game()
	else:
		_close_peer()
	selected_character = character_id
	_last_host = host
	_last_port = port
	_last_character = character_id
	_peer = ENetMultiplayerPeer.new()
	_peer.set_bind_ip(BIND_ADDRESS)
	var result := _peer.create_client(host, port)
	if result != OK:
		_peer = null
		if not _retry_in_flight:
			_fail("לא ניתן להתחבר למשחק")
		return result
	_is_host = false
	multiplayer.multiplayer_peer = _peer
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	if not _retry_in_flight:
		_set_state(CONNECTING)
	return OK


func leave_game() -> void:
	_close_peer()
	_is_host = false
	_characters_by_peer.clear()
	_resume_acks.clear()
	_resume_countdown_remaining = 0.0
	_paused = false
	_traffic_timer = 0.0
	_retry_in_flight = false
	_reconnect.reset()
	session_id = ""
	current_level_id = ""
	if state != IDLE:
		_set_state(IDLE)


func set_authoritative_snapshot(snapshot: Dictionary) -> void:
	_authoritative_snapshot = snapshot


func notify_traffic() -> void:
	_traffic_timer = 0.0


func simulate_connection_loss() -> void:
	if state != PLAYING and state != RECONNECTING:
		return
	if _paused and _reconnect.state == ReconnectController.RETRYING:
		return
	_paused = true
	paused.emit()
	_set_state(RECONNECTING)
	_close_peer()
	_reconnect.connection_lost(session_id)


func confirm_checkpoint(level_id: String, checkpoint_id: String, unlocked_levels: Array, hero_state: Dictionary) -> void:
	var payload := {
		"level_id": level_id,
		"checkpoint_id": checkpoint_id,
		"unlocked_levels": unlocked_levels,
		"hero_state": hero_state,
	}
	var checkpoint = CheckpointState.from_dict(payload)
	if checkpoint == null:
		return
	confirmed_checkpoint = checkpoint.to_dict()
	checkpoint_confirmed.emit(confirmed_checkpoint)
	_persist_checkpoint(confirmed_checkpoint)
	if _is_host and _peer != null:
		deliver_checkpoint_confirmation.rpc(confirmed_checkpoint)


@rpc("authority", "reliable")
func deliver_checkpoint_confirmation(checkpoint: Dictionary) -> void:
	if checkpoint.is_empty() or CheckpointState.from_dict(checkpoint) == null:
		return
	confirmed_checkpoint = checkpoint
	checkpoint_confirmed.emit(confirmed_checkpoint)
	_persist_checkpoint(checkpoint)


func configure_reconnect(retry_window: float, retry_interval: float) -> void:
	_reconnect.retry_window = retry_window
	_reconnect.retry_interval = retry_interval


func _begin_reconnect() -> void:
	if _paused:
		return
	_paused = true
	paused.emit()
	_set_state(RECONNECTING)
	_reconnect.connection_lost(session_id)


func _close_peer() -> void:
	_disconnect_multiplayer_signals()
	if multiplayer.multiplayer_peer == _peer and _peer != null:
		multiplayer.multiplayer_peer = null
	if _peer != null:
		_peer.close()
	_peer = null


func _disconnect_multiplayer_signals() -> void:
	if multiplayer.is_connected("peer_connected", _on_peer_connected):
		multiplayer.peer_connected.disconnect(_on_peer_connected)
	if multiplayer.is_connected("peer_disconnected", _on_peer_disconnected):
		multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
	if multiplayer.is_connected("connected_to_server", _on_connected_to_server):
		multiplayer.connected_to_server.disconnect(_on_connected_to_server)
	if multiplayer.is_connected("connection_failed", _on_connection_failed):
		multiplayer.connection_failed.disconnect(_on_connection_failed)
	if multiplayer.is_connected("server_disconnected", _on_server_disconnected):
		multiplayer.server_disconnected.disconnect(_on_server_disconnected)


func _on_peer_connected(peer_id: int) -> void:
	if not _is_host:
		return
	if _characters_by_peer.size() >= GameConfig.MAX_PLAYERS and not _paused:
		_peer.disconnect_peer(peer_id, true)
		return


func _last_character_for_peer(peer_id: int) -> String:
	if _characters_by_peer.has(peer_id):
		return _characters_by_peer[peer_id]
	return _other_character(selected_character)


func _on_peer_disconnected(peer_id: int) -> void:
	_characters_by_peer.erase(peer_id)
	if _is_host and state == PLAYING:
		_begin_reconnect()


func _on_connected_to_server() -> void:
	if _retry_in_flight:
		_retry_in_flight = false
	if _reconnect.state == ReconnectController.RETRYING:
		_set_state(LOBBY)
		request_resume.rpc(session_id)
		return
	_set_state(LOBBY)
	request_lobby_entry.rpc(Protocol.local_build_descriptor(), selected_character)


func _on_connection_failed() -> void:
	if _retry_in_flight:
		_retry_in_flight = false
		_close_peer()
		return
	_fail("החיבור נכשל")
	leave_game()


func _on_server_disconnected() -> void:
	if _reconnect.state == ReconnectController.RETRYING:
		return
	_fail("החיבור נותק")
	_begin_reconnect()


func _on_reconnect_state_changed(next_state: String) -> void:
	reconnect_state_changed.emit(next_state)


func _on_retry_scheduled(id: String) -> void:
	if _is_host or _last_host.is_empty():
		return
	_retry_in_flight = true
	join_game(_last_host, _last_port, _last_character)


func _on_reconnect_failed(id: String) -> void:
	_persist_checkpoint(confirmed_checkpoint)
	leave_game()


func _persist_checkpoint(checkpoint: Dictionary) -> void:
	if checkpoint.is_empty():
		return
	var store = get_node_or_null("/root/SaveStore")
	if store == null:
		return
	var data: Dictionary = store.load_data()
	data["confirmed_checkpoint"] = checkpoint
	store.save_data(data)


func _set_state(next_state: String) -> void:
	if state == next_state:
		return
	if not SessionState.is_valid_transition(state, next_state):
		return
	state = next_state
	state_changed.emit(state)


func _fail(message: String) -> void:
	session_error.emit(message)


func _complete_resume() -> void:
	_paused = false
	_traffic_timer = 0.0
	_resume_acks.clear()
	_resume_countdown_remaining = 0.0
	_reconnect.reset()
	_set_state(PLAYING)
	resumed.emit()


@rpc("any_peer", "reliable")
func request_lobby_entry(build: Dictionary, requested_character: String) -> void:
	if not _is_host:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var comparison := Protocol.compare_builds(Protocol.local_build_descriptor(), build)
	if not bool(comparison.get("compatible", false)):
		_reject_lobby_peer(peer_id, String(comparison.get("relation", "unknown")))
		return
	_accept_lobby_character(peer_id, requested_character)


func _reject_lobby_peer(peer_id: int, reason: String) -> void:
	reject_lobby_entry.rpc_id(peer_id, reason, Protocol.local_build_descriptor())
	get_tree().create_timer(0.1).timeout.connect(func() -> void:
		if _peer != null and _peer.get_peer(peer_id) != null:
			_peer.disconnect_peer(peer_id, true))


func _accept_lobby_character(peer_id: int, requested_character: String) -> void:
	if requested_character != "rabbit" and requested_character != "fox":
		_reject_lobby_peer(peer_id, "invalid_character")
		return
	var character_id := requested_character if not _characters_by_peer.values().has(requested_character) else _other_character(requested_character)
	if _characters_by_peer.values().has(character_id):
		_reject_lobby_peer(peer_id, "game_full")
		return
	_characters_by_peer[peer_id] = character_id
	confirm_lobby_entry.rpc_id(peer_id, character_id, session_id)
	peer_ready.emit(peer_id, character_id)
	_resume_acks.clear()
	_set_state(PLAYING)
	notify_traffic()


@rpc("authority", "reliable")
func confirm_lobby_entry(character_id: String, host_session_id: String) -> void:
	selected_character = character_id
	session_id = host_session_id
	peer_ready.emit(multiplayer.get_unique_id(), character_id)
	_set_state(PLAYING)
	notify_traffic()


@rpc("authority", "reliable")
func reject_lobby_entry(relation: String, _host_build: Dictionary) -> void:
	_fail(_message_for_lobby_rejection(relation))
	leave_game()


func _message_for_lobby_rejection(relation: String) -> String:
	match relation:
		"local_older":
			return "צריך לעדכן את הטאבלט הזה לפני המשחק"
		"remote_older":
			return "צריך לעדכן את הטאבלט השני לפני המשחק"
		"invalid_character":
			return "הדמות שנבחרה אינה זמינה"
		"game_full":
			return "המשחק מלא"
		_:
			return "גרסאות המשחק אינן תואמות. עדכנו את שני הטאבלטים"


@rpc("any_peer", "reliable")
func request_resume(requested_session_id: String) -> void:
	if not _is_host or not _paused:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id <= 0 or requested_session_id != session_id:
		return
	if not _characters_by_peer.has(peer_id):
		_characters_by_peer[peer_id] = _last_character_for_peer(peer_id)
	if not Protocol.valid_snapshot(_authoritative_snapshot):
		_authoritative_snapshot = _empty_snapshot()
	restore_session.rpc_id(peer_id, _authoritative_snapshot, _characters_by_peer[peer_id])


@rpc("authority", "reliable")
func restore_session(snapshot: Dictionary, character_id: String) -> void:
	if not Protocol.valid_snapshot(snapshot):
		return
	_authoritative_snapshot = snapshot
	if not character_id.is_empty():
		selected_character = character_id
	snapshot_received.emit(snapshot)
	acknowledge_resume.rpc_id(1)


@rpc("any_peer", "reliable")
func acknowledge_resume() -> void:
	if not _is_host or not _paused:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id <= 0:
		return
	_resume_acks[peer_id] = true
	if _resume_acks.size() >= _characters_by_peer.size() - 1 and _resume_countdown_remaining <= 0.0:
		_resume_countdown_remaining = RESUME_COUNTDOWN
		begin_resume_countdown.rpc()


@rpc("authority", "reliable")
func begin_resume_countdown() -> void:
	_resume_countdown_remaining = RESUME_COUNTDOWN


func _empty_snapshot() -> Dictionary:
	return {
		"tick": 0,
		"players": [{
			"peer_id": 1,
			"x": 0.0,
			"y": 0.0,
			"vx": 0.0,
			"vy": 0.0,
			"hearts": 3,
			"checkpoint": "start",
			"last_seq": 0,
		}],
	}


func _other_character(character_id: String) -> String:
	return "fox" if character_id == "rabbit" else "rabbit"


func _generate_session_id() -> String:
	var id := ""
	for index in 12:
		id += SESSION_ID_ALPHABET[randi() % SESSION_ID_ALPHABET.length()]
	return id
