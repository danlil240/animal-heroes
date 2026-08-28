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
	listener.host_found.connect(func(info: Dictionary) -> void: found.append(info))
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
	if listener.ingest_packet(PackedByteArray([1, 2, 3])):
		_fail("malformed advertisements must be ignored")
		return
	host.stop()
	listener.stop()
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
