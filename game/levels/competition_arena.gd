class_name CompetitionArena
extends TwoPlayerLevel

## Shared scaffolding for the friendly competitive arenas: stable peer
## identities for scoring and a single completion payload for the app shell.

const HOST_PEER_ID := 1
const GUEST_PEER_ID := 2

## Competition identifier for this arena; set on the scene root.
@export var level_id: String = ""


func _setup_level() -> void:
	if level_id.is_empty():
		push_error("competition arena must declare level_id")
	rabbit.set_meta("peer_id", HOST_PEER_ID)
	fox.set_meta("peer_id", GUEST_PEER_ID)
	_setup_arena()


func _setup_arena() -> void:
	pass


func _finish_match(result) -> void:
	var payload: Dictionary = {} if result == null else result.to_dict()
	payload["mode"] = "competition"
	payload["level_id"] = level_id
	finish_level(payload)
