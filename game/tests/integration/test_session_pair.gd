extends SceneTree

## Two-process LAN check: both peers reach PLAYING with distinct heroes, a third
## peer is refused, and the host's chosen level reaches the joining peer.

const SHARED_LEVEL := "crystal_caves"

var acknowledged_level := ""
var third_reached_playing := false
var incompatible_reached_playing := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var role := _argument_value("role")
	if role.is_empty():
		quit(0)
		return
	if role != "host" and role != "client" and role != "third" and role != "incompatible":
		_fail("role must be host, client, third, or incompatible")
		return
	var session = root.get_node_or_null("Session")
	if session == null:
		_fail("Session autoload must be present")
		return
	if role == "third" or role == "incompatible":
		session.state_changed.connect(_capture_third_state)
	var expected_playing := role != "third" and role != "incompatible"
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
	if not expected_playing and third_reached_playing:
		_fail("%s client was accepted" % role)
		return
	if role == "host":
		session.level_start_acknowledged.connect(_capture_level_ack)
		session.start_level(SHARED_LEVEL)
		var waited := 0.0
		while waited < 3.0 and acknowledged_level != SHARED_LEVEL:
			await create_timer(0.05).timeout
			waited += 0.05
		if acknowledged_level != SHARED_LEVEL:
			_fail("host did not receive the client's level acknowledgement")
			return
	elif role == "client":
		var waited := 0.0
		while waited < 3.0 and session.current_level_id.is_empty():
			await create_timer(0.05).timeout
			waited += 0.05
		if session.current_level_id != SHARED_LEVEL:
			_fail("client did not receive the host's level, got '%s'" % session.current_level_id)
			return
	if role == "third" or role == "incompatible":
		print("SESSION_RESULT role=%s accepted=false" % role)
	else:
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


func _capture_level_ack(_peer_id: int, level_id: String) -> void:
	acknowledged_level = level_id


func _capture_third_state(next_state: String) -> void:
	if next_state == "playing":
		third_reached_playing = true


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
