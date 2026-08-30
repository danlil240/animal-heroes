class_name BreakableBramble
extends Area2D

## A projectile-opened secret barrier. Only an active basic or spread bubble
## breaks it; the barrier emits `broken` exactly once and disables collision.

signal broken(bramble_id: String, owner_peer_id: int)

@export var bramble_id: String = ""

var _broken: bool = false
var _break_tween: Tween


func _ready() -> void:
	add_to_group("bramble")
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)


func try_projectile(node: Node) -> bool:
	if _broken or node == null or not node is Area2D:
		return false
	if not bool(node.get("active")):
		return false
	var kind := String(node.get("projectile_kind"))
	if kind not in ["basic", "spread"]:
		return false
	_broken = true
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	var shape := get_node_or_null("CollisionShape2D")
	if shape != null:
		shape.set_deferred("disabled", true)
	var peer_id := int(node.get("owner_peer_id"))
	_play_break_animation()
	broken.emit(bramble_id, peer_id)
	return true


func is_broken() -> bool:
	return _broken


func snapshot_state() -> Dictionary:
	return {
		"bramble_id": bramble_id,
		"broken": _broken,
	}


func restore_state(data: Dictionary) -> bool:
	if not data.has_all(["bramble_id", "broken"]):
		return false
	if typeof(data["bramble_id"]) != TYPE_STRING or String(data["bramble_id"]) != bramble_id:
		return false
	if typeof(data["broken"]) != TYPE_BOOL:
		return false
	_broken = bool(data["broken"])
	if _broken:
		set_deferred("monitoring", false)
		set_deferred("monitorable", false)
		var shape := get_node_or_null("CollisionShape2D")
		if shape != null:
			shape.set_deferred("disabled", true)
	return true


func _on_area_entered(area: Area2D) -> void:
	try_projectile(area)


func _play_break_animation() -> void:
	var visual := get_node_or_null("Visual") as Node2D
	if visual == null:
		return
	if _break_tween != null:
		_break_tween.kill()
	_break_tween = create_tween()
	_break_tween.tween_property(visual, "scale", Vector2(1.2, 0.4), 0.12)
	_break_tween.parallel().tween_property(visual, "modulate:a", 0.0, 0.25)
