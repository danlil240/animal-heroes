class_name SessionState
extends RefCounted


const IDLE := "idle"
const DISCOVERING := "discovering"
const CONNECTING := "connecting"
const LOBBY := "lobby"
const PLAYING := "playing"
const RECONNECTING := "reconnecting"

const _TRANSITIONS := {
	IDLE: [DISCOVERING, CONNECTING, LOBBY],
	DISCOVERING: [IDLE, CONNECTING],
	CONNECTING: [IDLE, LOBBY, RECONNECTING],
	LOBBY: [IDLE, PLAYING, RECONNECTING],
	PLAYING: [IDLE, RECONNECTING],
	RECONNECTING: [IDLE, LOBBY, PLAYING],
}


static func is_valid_transition(from: String, to: String) -> bool:
	return to in _TRANSITIONS.get(from, [])
