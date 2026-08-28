class_name CheckpointState
extends RefCounted


const MAX_LEVEL_ID_LENGTH: int = 32
const MAX_CHECKPOINT_ID_LENGTH: int = 32
const MAX_UNLOCKED_LEVELS: int = 16
const _ID_PATTERN := "^[A-Za-z0-9_-]{1,32}$"

var level_id: String = ""
var checkpoint_id: String = ""
var unlocked_levels: Array = []
var hero_state: Dictionary = {}


static func from_dict(data: Dictionary) -> RefCounted:
	if not data.has_all(["level_id", "checkpoint_id", "unlocked_levels", "hero_state"]):
		return null
	if typeof(data["level_id"]) != TYPE_STRING or typeof(data["checkpoint_id"]) != TYPE_STRING:
		return null
	if typeof(data["unlocked_levels"]) != TYPE_ARRAY or typeof(data["hero_state"]) != TYPE_DICTIONARY:
		return null
	if not _matches(_ID_PATTERN, data["level_id"]) or not _matches(_ID_PATTERN, data["checkpoint_id"]):
		return null
	var unlocked: Array = data["unlocked_levels"]
	if unlocked.size() > MAX_UNLOCKED_LEVELS:
		return null
	for level in unlocked:
		if typeof(level) != TYPE_STRING or not _matches(_ID_PATTERN, level):
			return null
	var state: Object = load("res://core/checkpoint_state.gd").new()
	state.level_id = data["level_id"]
	state.checkpoint_id = data["checkpoint_id"]
	state.unlocked_levels = unlocked.duplicate()
	state.hero_state = (data["hero_state"] as Dictionary).duplicate(true)
	return state


func to_dict() -> Dictionary:
	return {
		"level_id": level_id,
		"checkpoint_id": checkpoint_id,
		"unlocked_levels": unlocked_levels.duplicate(),
		"hero_state": hero_state.duplicate(true),
	}


func equals(other: RefCounted) -> bool:
	if other == null:
		return false
	return level_id == other.level_id and checkpoint_id == other.checkpoint_id and _arrays_match(unlocked_levels, other.unlocked_levels) and _dicts_match(hero_state, other.hero_state)


static func _matches(pattern: String, value: String) -> bool:
	var expression := RegEx.create_from_string(pattern)
	return expression.search(value) != null


static func _arrays_match(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for index in a.size():
		if a[index] != b[index]:
			return false
	return true


static func _dicts_match(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for key in a:
		if not b.has(key) or a[key] != b[key]:
			return false
	return true
