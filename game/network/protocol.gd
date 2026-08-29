class_name Protocol
extends RefCounted


const GameConfig = preload("res://core/game_config.gd")
const BuildInfo = preload("res://core/build_info.gd")
const MAX_PACKET_BYTES: int = 512
const _SESSION_ID_PATTERN := "^[A-Za-z0-9_-]{6,32}$"
const _IPV4_PATTERN := "^(?:(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])\\.){3}(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$"
const _VERSION_NAME_PATTERN := "^[0-9]+\\.[0-9]+\\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\\+[0-9A-Za-z.-]+)?$"
const _DISCOVERY_STATES := ["lobby"]


static func encode_discovery(session_id: String, state: String, host: String, port: int) -> PackedByteArray:
	if not _valid_discovery_values(session_id, state, host, port):
		return PackedByteArray()
	var packet := JSON.stringify({
		"session_id": session_id,
		"state": state,
		"host": host,
		"port": port,
		"build": local_build_descriptor(),
	}).to_utf8_buffer()
	return packet if packet.size() <= MAX_PACKET_BYTES else PackedByteArray()


static func decode_discovery(packet: PackedByteArray) -> Dictionary:
	if packet.is_empty() or packet.size() > MAX_PACKET_BYTES:
		return {}
	var json := JSON.new()
	if json.parse(packet.get_string_from_utf8()) != OK:
		return {}
	var parsed: Variant = json.data
	if not parsed is Dictionary:
		return {}
	var discovery: Dictionary = parsed
	if not _has_required_discovery_types(discovery):
		return {}
	if not _valid_discovery_values(discovery["session_id"], discovery["state"], discovery["host"], int(discovery["port"])):
		return {}
	discovery["port"] = int(discovery["port"])
	var build: Dictionary = discovery["build"]
	build["version_code"] = int(build["version_code"])
	build["application_protocol_version"] = int(build["application_protocol_version"])
	build["save_schema_version"] = int(build["save_schema_version"])
	discovery["build"] = build
	return discovery


static func local_build_descriptor() -> Dictionary:
	var build := BuildInfo.current()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--client-protocol="):
			var protocol_text := argument.trim_prefix("--client-protocol=")
			if protocol_text.is_valid_int() and int(protocol_text) > 0:
				build["application_protocol_version"] = int(protocol_text)
	return build


static func valid_build_descriptor(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var build: Dictionary = value
	if build.size() != 4 or not build.has_all(["version_name", "version_code", "application_protocol_version", "save_schema_version"]):
		return false
	return typeof(build["version_name"]) == TYPE_STRING and _matches(_VERSION_NAME_PATTERN, build["version_name"]) and typeof(build["version_code"]) == TYPE_INT and int(build["version_code"]) > 0 and typeof(build["application_protocol_version"]) == TYPE_INT and int(build["application_protocol_version"]) > 0 and typeof(build["save_schema_version"]) == TYPE_INT and int(build["save_schema_version"]) > 0


static func compare_builds(local: Dictionary, remote: Dictionary) -> Dictionary:
	if not valid_build_descriptor(local) or not valid_build_descriptor(remote):
		return {"compatible": false, "reason": "unknown", "relation": "unknown"}
	var relation := "same"
	if int(local["version_code"]) < int(remote["version_code"]):
		relation = "local_older"
	elif int(local["version_code"]) > int(remote["version_code"]):
		relation = "remote_older"
	var compatible := int(local["application_protocol_version"]) == int(remote["application_protocol_version"])
	return {
		"compatible": compatible,
		"reason": "ok" if compatible else "protocol_mismatch",
		"relation": relation,
	}


static func valid_input(frame: Dictionary) -> bool:
	if not frame.has_all(["seq", "axis", "jump", "action"]):
		return false
	if typeof(frame["seq"]) != TYPE_INT or frame["seq"] < 0:
		return false
	if (typeof(frame["axis"]) != TYPE_FLOAT and typeof(frame["axis"]) != TYPE_INT) or absf(float(frame["axis"])) > 1.0:
		return false
	return typeof(frame["jump"]) == TYPE_BOOL and typeof(frame["action"]) == TYPE_BOOL


static func valid_snapshot(snapshot: Dictionary) -> bool:
	if not snapshot.has_all(["tick", "players"]) or not _is_integral_number(snapshot["tick"]) or int(snapshot["tick"]) < 0:
		return false
	if not snapshot["players"] is Array or snapshot["players"].is_empty() or snapshot["players"].size() > GameConfig.MAX_PLAYERS:
		return false
	for player in snapshot["players"]:
		if not player is Dictionary or not player.has_all(["peer_id", "x", "y", "vx", "vy", "hearts", "checkpoint", "last_seq"]):
			return false
		if not _is_integral_number(player["peer_id"]) or int(player["peer_id"]) <= 0 or not _is_integral_number(player["hearts"]) or int(player["hearts"]) < 0 or int(player["hearts"]) > 4 or not _is_integral_number(player["last_seq"]) or int(player["last_seq"]) < 0 or typeof(player["checkpoint"]) != TYPE_STRING or not _matches("^[A-Za-z0-9_-]{1,32}$", player["checkpoint"]):
			return false
		for coordinate in ["x", "y", "vx", "vy"]:
			if not _is_number_in_range(player[coordinate], -100000.0, 100000.0):
				return false
	return true


static func _has_required_discovery_types(discovery: Dictionary) -> bool:
	if not discovery.has_all(["session_id", "state", "host", "port", "build"]):
		return false
	if typeof(discovery["session_id"]) != TYPE_STRING or typeof(discovery["state"]) != TYPE_STRING or typeof(discovery["host"]) != TYPE_STRING or not _is_integral_number(discovery["port"]) or not discovery["build"] is Dictionary:
		return false
	var build: Dictionary = discovery["build"]
	return build.size() == 4 and build.has_all(["version_name", "version_code", "application_protocol_version", "save_schema_version"]) and typeof(build["version_name"]) == TYPE_STRING and _matches(_VERSION_NAME_PATTERN, build["version_name"]) and _is_integral_number(build["version_code"]) and int(build["version_code"]) > 0 and _is_integral_number(build["application_protocol_version"]) and int(build["application_protocol_version"]) > 0 and _is_integral_number(build["save_schema_version"]) and int(build["save_schema_version"]) > 0


static func _valid_discovery_values(session_id: String, state: String, host: String, port: int) -> bool:
	return _matches(_SESSION_ID_PATTERN, session_id) and state in _DISCOVERY_STATES and _matches(_IPV4_PATTERN, host) and port > 0 and port <= 65535


static func _matches(pattern: String, value: String) -> bool:
	var expression := RegEx.create_from_string(pattern)
	return expression.search(value) != null


static func _is_integral_number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_equal_approx(float(value), roundf(float(value)))


static func _is_number_in_range(value: Variant, minimum: float, maximum: float) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and float(value) >= minimum and float(value) <= maximum
