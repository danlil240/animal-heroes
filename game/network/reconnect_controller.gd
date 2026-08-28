class_name ReconnectController
extends RefCounted


const IDLE := "idle"
const RETRYING := "retrying"
const RESTORED := "restored"
const FAILED := "failed"

const DEFAULT_RETRY_WINDOW: float = 15.0
const DEFAULT_RETRY_INTERVAL: float = 1.0

signal state_changed(next_state: String)
signal retry_scheduled(session_id: String)
signal restored(session_id: String)
signal failed(session_id: String)

var state: String = IDLE
var session_id: String = ""
var retry_window: float = DEFAULT_RETRY_WINDOW
var retry_interval: float = DEFAULT_RETRY_INTERVAL

var _elapsed: float = 0.0
var _retry_timer: float = 0.0


func connection_lost(id: String) -> void:
	session_id = id
	_elapsed = 0.0
	_retry_timer = 0.0
	_set_state(RETRYING)


func tick(delta: float) -> void:
	if state != RETRYING:
		return
	_elapsed += maxf(delta, 0.0)
	if _elapsed >= retry_window:
		_set_state(FAILED)
		failed.emit(session_id)
		return
	_retry_timer += maxf(delta, 0.0)
	if _retry_timer >= retry_interval:
		_retry_timer = 0.0
		retry_scheduled.emit(session_id)


func restore(id: String) -> void:
	if state != RETRYING:
		return
	if id != session_id or id.is_empty():
		return
	_set_state(RESTORED)
	restored.emit(session_id)


func reset() -> void:
	session_id = ""
	_elapsed = 0.0
	_retry_timer = 0.0
	_set_state(IDLE)


func remaining_time() -> float:
	if state != RETRYING:
		return 0.0
	return maxf(retry_window - _elapsed, 0.0)


func _set_state(next_state: String) -> void:
	if state == next_state:
		return
	state = next_state
	state_changed.emit(next_state)
