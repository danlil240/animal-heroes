extends SceneTree


func _init() -> void:
	var protocol = load("res://network/protocol.gd")
	if protocol == null:
		push_error("protocol implementation must exist")
		quit(1)
		return
	var passed := true
	passed = _test_discovery_round_trip(protocol) and passed
	passed = _test_rejects_malformed_or_incompatible_packets(protocol) and passed
	passed = _test_rejects_invalid_endpoint_and_session_values(protocol) and passed
	passed = _test_validates_player_inputs(protocol) and passed
	quit(0 if passed else 1)


func _test_discovery_round_trip(protocol) -> bool:
	var packet: PackedByteArray = protocol.encode_discovery("abc123", "lobby", "192.168.1.8", 28740)
	var decoded: Dictionary = protocol.decode_discovery(packet)
	if decoded.get("protocol") != 1 or decoded.get("content") != "1.0.0-dev.1" or decoded.get("session_id") != "abc123":
		return _fail("compatible discovery packet must round trip")
	if decoded.get("host") != "192.168.1.8" or decoded.get("port") != 28740 or decoded.get("state") != "lobby":
		return _fail("discovery packet must retain its endpoint and state")
	return true


func _test_rejects_malformed_or_incompatible_packets(protocol) -> bool:
	if not protocol.decode_discovery(PackedByteArray([1, 2, 3])).is_empty():
		return _fail("malformed discovery packet must be rejected")
	var oversized := PackedByteArray()
	oversized.resize(protocol.MAX_PACKET_BYTES + 1)
	if not protocol.decode_discovery(oversized).is_empty():
		return _fail("oversized discovery packet must be rejected")
	var incompatible := JSON.stringify({"protocol": 99, "content": "1.0.0", "session_id": "abc123", "state": "lobby", "host": "192.168.1.8", "port": 28740}).to_utf8_buffer()
	if not protocol.decode_discovery(incompatible).is_empty():
		return _fail("incompatible discovery packet must be rejected")
	return true


func _test_rejects_invalid_endpoint_and_session_values(protocol) -> bool:
	for invalid_session in ["short", "contains space", "too-long-session-id-which-exceeds-thirty-two"]:
		if not protocol.encode_discovery(invalid_session, "lobby", "192.168.1.8", 28740).is_empty():
			return _fail("invalid session id must not encode: %s" % invalid_session)
	for invalid_host in ["localhost", "192.168.1.999", "2001:db8::1"]:
		if not protocol.encode_discovery("abc123", "lobby", invalid_host, 28740).is_empty():
			return _fail("invalid IPv4 host must not encode: %s" % invalid_host)
	if not protocol.encode_discovery("abc123", "lobby", "192.168.1.8", 0).is_empty():
		return _fail("port zero must not encode")
	return true


func _test_validates_player_inputs(protocol) -> bool:
	if not protocol.valid_input({"seq": 10, "axis": 1.0, "jump": true, "action": false}):
		return _fail("valid input frame must be accepted")
	if protocol.valid_input({"seq": 9, "axis": 8.0, "jump": true, "action": false}):
		return _fail("out-of-range input axis must be rejected")
	if protocol.valid_input({"seq": -1, "axis": 0.0, "jump": false, "action": false}):
		return _fail("negative sequence must be rejected")
	return true


func _fail(message: String) -> bool:
	push_error(message)
	return false
