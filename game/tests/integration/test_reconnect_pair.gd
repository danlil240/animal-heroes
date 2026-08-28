extends SceneTree


const GameConfig = preload("res://core/game_config.gd")
const Protocol = preload("res://network/protocol.gd")
const ReconnectController = preload("res://network/reconnect_controller.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var role := _argument_value("role")
	if role.is_empty():
		quit(0)
		return
	if role != "host" and role != "client":
		_fail("role must be host or client")
		return
	var session = root.get_node_or_null("Session")
	if session == null:
		_fail("Session autoload must be present")
		return
	# Fast retry window so the unrecoverable timeout stays bounded in tests.
	session.configure_reconnect(2.0, 0.2)
	var result: Error = session.create_game() if role == "host" else session.join_game("127.0.0.1", GameConfig.GAME_PORT, "rabbit")
	if result != OK:
		_fail("%s could not start its session" % role)
		return
	# Wait until both peers reach PLAYING.
	var elapsed := 0.0
	while elapsed < 5.0 and session.state != session.PLAYING:
		await create_timer(0.05).timeout
		elapsed += 0.05
	if session.state != session.PLAYING:
		_fail("%s did not reach PLAYING" % role)
		return
	# Host confirms a checkpoint; the RPC mirrors it to the client.
	if role == "host":
		session.set_authoritative_snapshot(_sample_snapshot())
		session.confirm_checkpoint("test_arena", "cp-1", ["sunny_forest"], {"peer_id": 1, "hearts": 3})
	# Allow the checkpoint RPC to propagate before simulating the outage.
	await create_timer(1.0).timeout
	# Simulate an unrecoverable outage on both sides.
	session.simulate_connection_loss()
	if session.state != session.RECONNECTING:
		_fail("%s did not enter reconnecting after loss" % role)
		return
	# Wait beyond the retry window so the controller fails and returns to IDLE.
	await create_timer(4.0).timeout
	if session.state == session.PLAYING:
		_fail("%s resumed without a live peer" % role)
		return
	# The confirmed checkpoint must survive the outage on both peers.
	var checkpoint: Dictionary = session.confirmed_checkpoint
	if checkpoint.is_empty() or checkpoint.get("checkpoint_id") != "cp-1":
		_fail("%s did not preserve the confirmed checkpoint" % role)
		return
	# The save must remain loadable and contain the mirrored checkpoint.
	var store = root.get_node_or_null("SaveStore")
	if store != null:
		var data: Dictionary = store.load_data()
		if data.get("confirmed_checkpoint", {}).get("checkpoint_id") != "cp-1":
			_fail("%s save did not mirror the confirmed checkpoint" % role)
			return
	print("RECONNECT_RESULT role=%s state=%s checkpoint=%s" % [role, session.state, checkpoint.get("checkpoint_id")])
	session.leave_game()
	quit(0)


func _sample_snapshot() -> Dictionary:
	return {
		"tick": 1,
		"players": [{
			"peer_id": 1,
			"x": 100.0,
			"y": 200.0,
			"vx": 0.0,
			"vy": 0.0,
			"hearts": 3,
			"checkpoint": "cp-1",
			"last_seq": 0,
		}],
	}


func _argument_value(name: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--%s=" % name):
			return argument.trim_prefix("--%s=" % name)
	return ""


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
