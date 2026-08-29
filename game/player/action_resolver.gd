class_name ActionResolver
extends RefCounted

## Selects one action target without mutating it. Selection remains stable when
## scene-tree or network arrival order changes.


func select(hero: Node2D, candidates: Array, max_distance: float = 96.0) -> Node2D:
	if hero == null or max_distance < 0.0:
		return null
	var eligible: Array[Node2D] = []
	for candidate in candidates:
		if not candidate is Node2D or not is_instance_valid(candidate):
			continue
		var target := candidate as Node2D
		if hero.global_position.distance_to(target.global_position) > max_distance:
			continue
		if target.has_method("eligible_for") and not bool(target.eligible_for(hero)):
			continue
		eligible.append(target)
	eligible.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		var a_priority := int(a.get("interaction_priority"))
		var b_priority := int(b.get("interaction_priority"))
		if a_priority != b_priority:
			return a_priority > b_priority
		var a_distance := hero.global_position.distance_squared_to(a.global_position)
		var b_distance := hero.global_position.distance_squared_to(b.global_position)
		if not is_equal_approx(a_distance, b_distance):
			return a_distance < b_distance
		return String(a.get("interaction_id")) < String(b.get("interaction_id"))
	)
	return null if eligible.is_empty() else eligible[0]
