class_name MatchResult
extends RefCounted


var winner_peer_id: int = 0
var scores: Dictionary = {}
var finish_order: Array[int] = []
var reason: String = ""


func _init(winner: int = 0, score_map: Dictionary = {}, order: Array[int] = [], result_reason: String = "") -> void:
	winner_peer_id = winner
	scores = score_map.duplicate()
	finish_order = order.duplicate()
	reason = result_reason


func to_dict() -> Dictionary:
	return {
		"winner_peer_id": winner_peer_id,
		"scores": scores.duplicate(),
		"finish_order": finish_order.duplicate(),
		"reason": reason,
	}


func is_tie() -> bool:
	return winner_peer_id == 0
