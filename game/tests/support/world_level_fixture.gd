extends "res://levels/two_player_level.gd"

var applied_event_count: int = 0
var applied_payloads: Array[Dictionary] = []


func _validate_world_action(peer_id: int, action_id: String, target_id: String, hero_position: Vector2) -> Dictionary:
	if peer_id != 2 or action_id != "push" or target_id != "log":
		return {}
	if hero_position.distance_to(Vector2.ZERO) > 96.0:
		return {}
	return {"kind": "gate_part", "payload": {"target_id": target_id, "peer_id": peer_id}}


func _apply_world_event(_sequence: int, _kind: String, payload: Dictionary) -> void:
	applied_event_count += 1
	applied_payloads.append(payload.duplicate(true))
