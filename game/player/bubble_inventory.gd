class_name BubbleInventory
extends RefCounted

## The host owns each hero's temporary spread charges. Basic fire is unlimited
## and therefore has no stored entry.

const BASIC: String = "basic"
const SPREAD: String = "spread"
const MAX_POWERED_SHOTS: int = 10

var _powered: Dictionary = {}


func grant_spread(peer_id: int, amount: int = MAX_POWERED_SHOTS) -> int:
	if not _is_hero_peer(peer_id):
		return 0
	var current := remaining(peer_id)
	var next_count := mini(MAX_POWERED_SHOTS, current + maxi(amount, 0))
	if next_count > 0:
		_powered[peer_id] = {"kind": SPREAD, "remaining": next_count}
	return next_count


func consume_spread(peer_id: int) -> bool:
	if not _is_hero_peer(peer_id):
		return false
	var current := remaining(peer_id)
	if current <= 0:
		return false
	if current == 1:
		_powered.erase(peer_id)
	else:
		_powered[peer_id] = {"kind": SPREAD, "remaining": current - 1}
	return true


func kind(peer_id: int) -> String:
	return SPREAD if remaining(peer_id) > 0 else BASIC


func remaining(peer_id: int) -> int:
	if not _is_hero_peer(peer_id):
		return 0
	var entry: Variant = _powered.get(peer_id, {})
	if not entry is Dictionary:
		return 0
	return int(entry.get("remaining", 0))


## Compatibility for the pre-powered Sunny Forest flow. New callers should use
## grant_spread(), but the legacy name now follows the ten-charge contract too.
func grant(peer_id: int, amount: int = MAX_POWERED_SHOTS) -> int:
	return grant_spread(peer_id, amount)


## Compatibility for callers that already gate fire on remaining().
func consume(peer_id: int) -> bool:
	return consume_spread(peer_id)


func snapshot() -> Dictionary:
	return _powered.duplicate(true)


func restore(data: Dictionary) -> bool:
	var next_powered: Dictionary = {}
	var seen_peers: Dictionary = {}
	for raw_peer_id in data:
		var peer_id: int
		if typeof(raw_peer_id) == TYPE_INT:
			peer_id = raw_peer_id
		elif typeof(raw_peer_id) == TYPE_STRING and String(raw_peer_id).is_valid_int():
			peer_id = int(raw_peer_id)
		else:
			return false
		if not _is_hero_peer(peer_id) or seen_peers.has(peer_id):
			return false
		seen_peers[peer_id] = true
		var raw_entry: Variant = data[raw_peer_id]
		if not raw_entry is Dictionary:
			return false
		var entry: Dictionary = raw_entry
		if entry.size() != 2 or not entry.has("kind") or not entry.has("remaining"):
			return false
		var entry_kind: Variant = entry["kind"]
		var entry_remaining: Variant = entry["remaining"]
		if typeof(entry_kind) != TYPE_STRING or String(entry_kind) not in [BASIC, SPREAD]:
			return false
		if typeof(entry_remaining) != TYPE_INT:
			return false
		var count: int = entry_remaining
		if count < 0 or count > MAX_POWERED_SHOTS:
			return false
		if entry_kind == BASIC and count != 0:
			return false
		if entry_kind == SPREAD and count > 0:
			next_powered[peer_id] = {"kind": SPREAD, "remaining": count}
	_powered = next_powered
	return true


func _is_hero_peer(peer_id: int) -> bool:
	return peer_id == 1 or peer_id == 2
