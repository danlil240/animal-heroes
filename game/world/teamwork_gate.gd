class_name TeamworkGate
extends RefCounted

## Deterministic multi-part cooperative gate with reconnect-safe state.

signal completed(gate_id: String)

var gate_id: String = ""
var _required_parts: Array[String] = []
var _active_parts: Dictionary = {}
var _completed: bool = false


func configure(id: String, required_parts: Array) -> void:
	gate_id = id
	_required_parts.clear()
	for raw_part in required_parts:
		var part_id := String(raw_part)
		if not part_id.is_empty() and not _required_parts.has(part_id):
			_required_parts.append(part_id)
	_required_parts.sort()
	_active_parts.clear()
	_completed = false


func mark_part(part_id: String, peer_id: int) -> bool:
	if _completed or peer_id <= 0 or not _required_parts.has(part_id) or _active_parts.has(part_id):
		return false
	_active_parts[part_id] = peer_id
	if _active_parts.size() < _required_parts.size():
		return false
	_completed = true
	completed.emit(gate_id)
	return true


func is_complete() -> bool:
	return _completed


func snapshot() -> Dictionary:
	return {
		"gate_id": gate_id,
		"required_parts": _required_parts.duplicate(),
		"active_parts": _active_parts.duplicate(true),
		"completed": _completed,
	}


func restore(data: Dictionary) -> bool:
	if String(data.get("gate_id", "")) != gate_id:
		return false
	var required: Variant = data.get("required_parts", null)
	var active: Variant = data.get("active_parts", null)
	var completed_value: Variant = data.get("completed", null)
	if not required is Array or not active is Dictionary or not completed_value is bool:
		return false
	var normalized_required: Array[String] = []
	for raw_part in required:
		var part_id := String(raw_part)
		if part_id.is_empty() or normalized_required.has(part_id):
			return false
		normalized_required.append(part_id)
	normalized_required.sort()
	if normalized_required != _required_parts:
		return false
	var next_active: Dictionary = {}
	for raw_part in active:
		var part_id := String(raw_part)
		var peer_id := int(active[raw_part])
		if not _required_parts.has(part_id) or peer_id <= 0:
			return false
		next_active[part_id] = peer_id
	var should_be_complete := next_active.size() == _required_parts.size() and not _required_parts.is_empty()
	if bool(completed_value) != should_be_complete:
		return false
	_active_parts = next_active
	_completed = should_be_complete
	return true
