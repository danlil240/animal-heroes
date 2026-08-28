class_name CoopMode
extends RefCounted


signal checkpoint_confirmed(checkpoint_id: String)
signal level_completed(level_id: String)
signal campaign_completed(unlocked_levels: Array)

var level_id: String = ""
var current_checkpoint_id: String = ""
var unlocked_levels: Array = []
var confirmation_count: int = 0
var _completed: bool = false
var _campaign_completed: bool = false
const CAMPAIGN_LEVELS: Array = ["sunny_forest", "crystal_caves", "cloud_factory", "robot_boss"]


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
	_check_campaign_completion()


func complete_campaign() -> void:
	for level in CAMPAIGN_LEVELS:
		if not unlocked_levels.has(level):
			unlocked_levels.append(level)
	if not _campaign_completed:
		_campaign_completed = true
		campaign_completed.emit(unlocked_levels.duplicate())


func is_campaign_completed() -> bool:
	return _campaign_completed


func _check_campaign_completion() -> void:
	var all_complete := true
	for level in CAMPAIGN_LEVELS:
		if not unlocked_levels.has(level):
			all_complete = false
			break
	if all_complete and not _campaign_completed:
		_campaign_completed = true
		campaign_completed.emit(unlocked_levels.duplicate())


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
