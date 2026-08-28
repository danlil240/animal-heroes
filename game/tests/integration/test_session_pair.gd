extends SceneTree

## Two-process LAN check: both peers reach PLAYING with distinct heroes, a third
## peer is refused, and the host's chosen level reaches the joining peer.

const SHARED_LEVEL := "crystal_caves"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var role := _argument_value("role")
	if role.is_empty():
		quit(0)
		return
	if role != "host" and role != "client" and role != "third":
		_fail("role must be host, client, or third")
		return
	var session = root.get_node_or_null("Session")
	if session == null:
		_fail("Session autoload must be present")
		return
	var expected_playing := role != "third"
	var result: Error = session.create_game() if role == "host" else session.join_game("127.0.0.1", 28740, "rabbit")
	if result != OK:
		_fail("%s could not start its session" % role)
		return
	var elapsed := 0.0
	while elapsed < 5.0 and (session.state != session.PLAYING if expected_playing else session.state != session.IDLE):
		await create_timer(0.05).timeout
		elapsed += 0.05
	if expected_playing and session.state != session.PLAYING:
		_fail("%s did not reach PLAYING" % role)
		return
	if not expected_playing and session.state == session.PLAYING:
		_fail("third client was accepted")
		return
	if role == "host":
		session.start_level(SHARED_LEVEL)
	elif role == "client":
		var waited := 0.0
		while waited < 3.0 and session.current_level_id.is_empty():
			await create_timer(0.05).timeout
			waited += 0.05
		if session.current_level_id != SHARED_LEVEL:
			_fail("client did not receive the host's level, got '%s'" % session.current_level_id)
			return
	print("SESSION_RESULT role=%s state=%s character=%s level=%s" % [role, session.state, session.selected_character, session.current_level_id])
	if role == "client":
		await create_timer(2.0).timeout
	session.leave_game()
	quit(0)


func _argument_value(name: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--%s=" % name):
			return argument.trim_prefix("--%s=" % name)
	return ""


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
