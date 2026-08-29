class_name BubbleInventory
extends RefCounted

## Per-peer bounded bubble ammunition. The host is the authoritative writer.

const MAX_AMMO: int = 5

var _ammo: Dictionary = {}


func grant(peer_id: int, amount: int = MAX_AMMO) -> int:
	if peer_id <= 0:
		return 0
	_ammo[peer_id] = mini(MAX_AMMO, int(_ammo.get(peer_id, 0)) + maxi(amount, 0))
	return int(_ammo[peer_id])


func consume(peer_id: int) -> bool:
	var count := remaining(peer_id)
	if count <= 0:
		return false
	_ammo[peer_id] = count - 1
	return true


func remaining(peer_id: int) -> int:
	return int(_ammo.get(peer_id, 0))


func snapshot() -> Dictionary:
	return _ammo.duplicate(true)


func restore(data: Dictionary) -> bool:
	var next_ammo: Dictionary = {}
	for raw_peer_id in data:
		var peer_id := int(raw_peer_id)
		var count := int(data[raw_peer_id])
		if peer_id <= 0 or count < 0 or count > MAX_AMMO:
			return false
		next_ammo[peer_id] = count
	_ammo = next_ammo
	return true
