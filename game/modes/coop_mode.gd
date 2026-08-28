class_name CoopMode
extends RefCounted


signal checkpoint_confirmed(checkpoint_id: String)
signal level_completed(level_id: String)

var level_id: String = ""
var current_checkpoint_id: String = ""
var unlocked_levels: Array = []
var confirmation_count: int = 0
var _completed: bool = false


func start(id: String, unlocked: Array) -> void:
	level_id = id
	current_checkpoint_id = ""
	unlocked_levels = unlocked.duplicate()
	confirmation_count = 0
	_completed = false


func confirm_checkpoint(checkpoint_id: String) -> void:
	if checkpoint_id.is_empty() or checkpoint_id == current_checkpoint_id:
		return
	current_checkpoint_id = checkpoint_id
	confirmation_count += 1
	if not unlocked_levels.has(level_id):
		unlocked_levels.append(level_id)
	checkpoint_confirmed.emit(checkpoint_id)


func complete_level() -> void:
	if _completed:
		return
	_completed = true
	if not unlocked_levels.has(level_id):
		unlocked_levels.append(level_id)
	level_completed.emit(level_id)


func is_completed() -> bool:
	return _completed


func to_dict() -> Dictionary:
	return {
		"level_id": level_id,
		"current_checkpoint_id": current_checkpoint_id,
		"unlocked_levels": unlocked_levels.duplicate(),
		"confirmation_count": confirmation_count,
		"completed": _completed,
	}
