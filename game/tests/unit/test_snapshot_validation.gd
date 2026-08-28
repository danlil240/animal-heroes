extends SceneTree


const Protocol = preload("res://network/protocol.gd")


func _init() -> void:
	var snapshot := {
		"tick": 20,
		"players": [{"peer_id": 1, "x": 320.0, "y": 480.0, "vx": 0.0, "vy": 0.0, "hearts": 3, "checkpoint": "start", "last_seq": 18}],
	}
	if not Protocol.valid_snapshot(snapshot):
		_fail("bounded authoritative snapshot must be accepted")
		return
	snapshot["players"][0]["hearts"] = 99
	if Protocol.valid_snapshot(snapshot):
		_fail("out-of-range hearts must be rejected")
		return
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
