class_name PartnerIndicator
extends Control

const INSET: float = 28.0

@onready var arrow: Polygon2D = $Arrow

var inset: float = INSET
var viewport_size_override: Vector2 = Vector2.ZERO
var _local_world_position: Vector2
var _partner_world_position: Variant = null


func update_for_world_positions(local_position: Vector2, partner_position: Variant) -> void:
	_local_world_position = local_position
	_partner_world_position = partner_position
	if partner_position == null:
		hide()
		return
	var canvas_transform := get_viewport().get_canvas_transform()
	var local_screen := canvas_transform * local_position
	var partner_screen := canvas_transform * (partner_position as Vector2)
	var viewport_size := _viewport_size()
	if _inside_full_viewport(partner_screen, viewport_size):
		hide()
		return
	var inset_rect := Rect2(Vector2(inset, inset), viewport_size - Vector2(inset * 2.0, inset * 2.0))
	position = _ray_to_inset_edge(local_screen, partner_screen, inset_rect)
	arrow.rotation = (partner_screen - local_screen).angle()
	show()


func is_on_inset_edge() -> bool:
	if not visible:
		return false
	var size := _viewport_size()
	return is_equal_approx(position.x, inset) or is_equal_approx(position.x, size.x - inset) or is_equal_approx(position.y, inset) or is_equal_approx(position.y, size.y - inset)


func _ray_to_inset_edge(from: Vector2, toward: Vector2, bounds: Rect2) -> Vector2:
	var direction := toward - from
	if direction.length_squared() <= 0.000001:
		return from.clamp(bounds.position, bounds.end)
	var candidates: Array[Dictionary] = []
	if absf(direction.x) > 0.000001:
		for side_x_value in [bounds.position.x, bounds.end.x]:
			var side_x: float = side_x_value
			var t: float = (side_x - from.x) / direction.x
			var point: Vector2 = from + direction * t
			if _valid_side_intersection(t, point, bounds):
				candidates.append({"t": t, "point": point})
	if absf(direction.y) > 0.000001:
		for side_y_value in [bounds.position.y, bounds.end.y]:
			var side_y: float = side_y_value
			var t: float = (side_y - from.y) / direction.y
			var point: Vector2 = from + direction * t
			if _valid_side_intersection(t, point, bounds):
				candidates.append({"t": t, "point": point})
	var nearest: Variant = null
	for candidate in candidates:
		if nearest == null or candidate.t < nearest.t:
			nearest = candidate
	if nearest != null:
		return nearest.point
	# An outward ray that never meets the inset uses this explicit finite fallback.
	return from.clamp(bounds.position, bounds.end)


func _viewport_size() -> Vector2:
	return viewport_size_override if viewport_size_override != Vector2.ZERO else get_viewport().get_visible_rect().size


func _inside_full_viewport(point: Vector2, size: Vector2) -> bool:
	return point.x >= 0.0 and point.x <= size.x and point.y >= 0.0 and point.y <= size.y


func _valid_side_intersection(t: float, point: Vector2, bounds: Rect2) -> bool:
	var epsilon := 0.0001
	return is_finite(t) and point.is_finite() and t >= 0.0 and point.x >= bounds.position.x - epsilon and point.x <= bounds.end.x + epsilon and point.y >= bounds.position.y - epsilon and point.y <= bounds.end.y + epsilon
