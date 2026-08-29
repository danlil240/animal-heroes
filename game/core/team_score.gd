class_name TeamScore
extends RefCounted

## Host-owned cooperative score with replay protection.

const VALUES := {
	"star": 10,
	"enemy": 25,
	"teamwork": 100,
	"secret": 100,
}

var total: int = 0
var _awarded_ids: Dictionary = {}


func award(event_id: String, category: String, multiplier: int = 1) -> int:
	if event_id.is_empty() or _awarded_ids.has(event_id) or not VALUES.has(category):
		return 0
	var points: int = int(VALUES[category]) * clampi(multiplier, 1, 4)
	_awarded_ids[event_id] = true
	total += points
	return points


func snapshot() -> Dictionary:
	var ids: Array = _awarded_ids.keys()
	ids.sort()
	return {
		"total": total,
		"awarded_ids": ids,
	}


func restore(data: Dictionary) -> bool:
	var next_total: int = int(data.get("total", -1))
	var ids: Variant = data.get("awarded_ids", null)
	if next_total < 0 or not ids is Array:
		return false
	var next_ids: Dictionary = {}
	for raw_id in ids:
		var event_id := String(raw_id)
		if event_id.is_empty() or next_ids.has(event_id):
			return false
		next_ids[event_id] = true
	total = next_total
	_awarded_ids = next_ids
	return true
