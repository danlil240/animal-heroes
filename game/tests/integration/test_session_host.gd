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
	session.leave_game()
	if session.state != session.IDLE:
		_fail("leaving must restore idle state")
		return
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
