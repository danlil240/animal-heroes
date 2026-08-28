class_name Door
extends StaticBody2D


signal opened(door_id: String)
signal closed(door_id: String)

@export var door_id: String = ""
@export var paired_switch_ids: Array = []
@export var open_on_all_active: bool = true

var _active_switches: Dictionary = {}
var _is_open: bool = false


func _ready() -> void:
	if door_id.is_empty():
		door_id = name.to_snake_case()


func switch_activated(switch_id: String) -> void:
	if not paired_switch_ids.has(switch_id):
		return
	_active_switches[switch_id] = true
	_check_state()


func switch_deactivated(switch_id: String) -> void:
	_active_switches.erase(switch_id)
	_check_state()


func _check_state() -> void:
	var all_active := _active_switches.size() >= paired_switch_ids.size()
	if open_on_all_active and all_active and not _is_open:
		_open()
	elif not all_active and _is_open:
		_close()


func _open() -> void:
	_is_open = true
	set_deferred("monitoring", false)
	visible = false
	opened.emit(door_id)


func _close() -> void:
	_is_open = false
	set_deferred("monitoring", true)
	visible = true
	closed.emit(door_id)


func is_open() -> bool:
	return _is_open


func reset() -> void:
	_active_switches.clear()
	_is_open = false
	visible = true
