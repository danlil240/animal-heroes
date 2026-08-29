extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var session_script = load("res://autoload/session.gd")
	if session_script == null:
		_fail("session facade must exist")
		return
	var session = session_script.new()
	root.add_child(session)
	if session.create_game() != OK:
		_fail("session must create an ENet host")
		return
	if session.state != session.LOBBY:
		_fail("new host must wait in the lobby")
		return
	if not session.is_host():
		_fail("session must expose the local host role without exposing peer internals")
		return
	var snapshot := {
		"tick": 1,
		"players": [{"peer_id": 1, "x": 0.0, "y": 0.0, "vx": 0.0, "vy": 0.0, "hearts": 3, "checkpoint": "start", "last_seq": 0}],
		"world": {"score": 10},
	}
	session.set_authoritative_snapshot(snapshot)
	var copy: Dictionary = session.authoritative_snapshot()
	copy["world"]["score"] = 999
	if session.authoritative_snapshot().get("world", {}).get("score") != 10:
		_fail("authoritative snapshot accessor must return a deep copy")
		return
	session.leave_game()
	if session.is_host():
		_fail("leaving the game must clear the exposed host role")
		return
	if session.state != session.IDLE:
		_fail("leaving must restore idle state")
		return
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
