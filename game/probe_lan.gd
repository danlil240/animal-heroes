extends SceneTree

var session: Node = null
var role := ""


func _target() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--target="):
			return argument.trim_prefix("--target=")
	return "127.0.0.1"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--role="):
			role = argument.trim_prefix("--role=")
	session = root.get_node_or_null("Session")
	print("[%s] session=%s" % [role, session])
	session.state_changed.connect(func(s): print("[%s] state -> %s" % [role, s]))
	session.session_error.connect(func(m): print("[%s] ERROR %s" % [role, m]))
	session.peer_ready.connect(func(p, c): print("[%s] peer_ready %d %s" % [role, p, c]))
	var multiplayer_api := session.multiplayer
	multiplayer_api.peer_connected.connect(func(id): print("[%s] mp.peer_connected %d" % [role, id]))
	multiplayer_api.connected_to_server.connect(func(): print("[%s] mp.connected_to_server" % role))
	multiplayer_api.connection_failed.connect(func(): print("[%s] mp.connection_failed" % role))
	multiplayer_api.server_disconnected.connect(func(): print("[%s] mp.server_disconnected" % role))
	var result: Error = session.create_game() if role == "host" else session.join_game(_target(), 28740, "rabbit")
	print("[%s] start result=%d state=%s" % [role, result, session.state])
	print("[%s] multiplayer_poll=%s" % [role, str(multiplayer_poll)])
	var elapsed := 0.0
	while elapsed < 6.0:
		await create_timer(0.25).timeout
		elapsed += 0.25
		session.multiplayer.poll()
		print("[%s] t=%.2f state=%s status=%s" % [role, elapsed, session.state, str(session.multiplayer.multiplayer_peer.get_connection_status())])
	quit(0)
