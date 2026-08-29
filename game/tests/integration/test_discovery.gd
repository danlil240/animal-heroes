extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var service_script = load("res://network/discovery_service.gd")
	if service_script == null:
		_fail("discovery service must exist")
		return
	var listener = service_script.new()
	var host = service_script.new()
	root.add_child(listener)
	root.add_child(host)
	host.broadcast_address = "127.0.0.1"
	var found: Array[Dictionary] = []
	var incompatible: Array[Dictionary] = []
	listener.host_found.connect(func(info: Dictionary) -> void: found.append(info))
	if not listener.has_signal("incompatible_host_found"):
		_fail("discovery service must signal incompatible advertisements")
		return
	listener.incompatible_host_found.connect(func(info: Dictionary) -> void: incompatible.append(info))
	if listener.listen() != OK:
		_fail("discovery listener must bind")
		return
	if host.host("abc123", "127.0.0.1", 28740) != OK:
		_fail("discovery host must begin advertising")
		return
	var protocol = load("res://network/protocol.gd")
	if not listener.ingest_packet(protocol.encode_discovery("abc123", "lobby", "127.0.0.1", 28740)):
		_fail("discovery service must accept a compatible advertisement")
		return
	if found.size() != 1 or found[0].get("session_id") != "abc123" or found[0].get("host") != "127.0.0.1" or found[0].get("port") != 28740:
		_fail("compatible host must be reported")
		return
	var incompatible_packet := JSON.stringify({
		"session_id": "def456",
		"state": "lobby",
		"host": "127.0.0.1",
		"port": 28740,
		"build": {"version_name": "2.0.0", "version_code": 2, "application_protocol_version": 99, "save_schema_version": 1},
	}).to_utf8_buffer()
	if not listener.ingest_packet(incompatible_packet):
		_fail("discovery service must classify a valid incompatible advertisement")
		return
	if incompatible.size() != 1 or incompatible[0].get("session_id") != "def456" or listener.known_hosts().size() != 1:
		_fail("incompatible advertisements must signal without becoming joinable hosts")
		return
	if not await _test_game_shell_uses_discovery_host():
		return
	if listener.ingest_packet(PackedByteArray([1, 2, 3])):
		_fail("malformed advertisements must be ignored")
		return
	host.stop()
	listener.stop()
	quit(0)


func _test_game_shell_uses_discovery_host() -> bool:
	var shell_scene: PackedScene = load("res://ui/game_shell.tscn")
	var shell = shell_scene.instantiate()
	root.add_child(shell)
	await process_frame
	var session = root.get_node("Session")
	session.leave_game()
	session.begin_discovery()
	shell._on_host_found({"host": "127.0.0.1", "port": 28740})
	if session.state != session.CONNECTING:
		root.remove_child(shell)
		shell.queue_free()
		return _fail_bool("GameShell must join using the advertised host key")
	session.leave_game()
	root.remove_child(shell)
	shell.queue_free()
	return true


func _fail_bool(message: String) -> bool:
	_fail(message)
	return false


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
