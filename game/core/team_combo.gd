class_name TeamCombo
extends RefCounted

## Shared cooperative scoring chain. Callers preview before awarding so rejected
## duplicate score events cannot advance or refresh the combo.

const WINDOW: float = 2.5
const MAX_MULTIPLIER: int = 4

var multiplier: int = 1
var remaining: float = 0.0


func preview_multiplier() -> int:
	return mini(multiplier + 1, MAX_MULTIPLIER) if remaining > 0.0 else 1


func commit_scored_event() -> void:
	multiplier = preview_multiplier()
	remaining = WINDOW


func refresh() -> void:
	if remaining > 0.0:
		remaining = WINDOW


func step(delta: float) -> void:
	if remaining <= 0.0:
		return
	remaining = maxf(remaining - maxf(delta, 0.0), 0.0)
	if remaining <= 0.0:
		multiplier = 1


func snapshot() -> Dictionary:
	return {
		"multiplier": multiplier,
		"remaining": remaining,
	}


func restore(data: Dictionary) -> bool:
	if not data.has_all(["multiplier", "remaining"]):
		return false
	if typeof(data["multiplier"]) != TYPE_INT:
		return false
	if typeof(data["remaining"]) != TYPE_INT and typeof(data["remaining"]) != TYPE_FLOAT:
		return false
	var next_multiplier := int(data["multiplier"])
	var next_remaining := float(data["remaining"])
	if next_multiplier < 1 or next_multiplier > MAX_MULTIPLIER:
		return false
	if not is_finite(next_remaining) or next_remaining < 0.0 or next_remaining > WINDOW:
		return false
	if next_remaining == 0.0 and next_multiplier != 1:
		return false
	multiplier = next_multiplier
	remaining = next_remaining
	return true
