class_name ObjectPool
extends RefCounted


signal object_acquired(node: Node)
signal object_released(node: Node)

var _scene: PackedScene
var _capacity: int = 0
var _available: Array[Node] = []
var _active: Array[Node] = []


func configure(scene: PackedScene, capacity: int) -> void:
	_scene = scene
	_capacity = max(capacity, 0)
	_available.clear()
	_active.clear()


func acquire() -> Node:
	if _scene == null or _capacity <= 0:
		return null
	if _active.size() >= _capacity and _available.is_empty():
		return null
	var node: Node = _available.pop_back() if not _available.is_empty() else _scene.instantiate()
	if node == null:
		return null
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	_active.append(node)
	object_acquired.emit(node)
	return node


func release(node: Node) -> void:
	if node == null:
		return
	_active.erase(node)
	if node.has_method("reset_for_pool"):
		node.reset_for_pool()
	if _available.size() < _capacity:
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		_available.append(node)
		object_released.emit(node)


func active_count() -> int:
	return _active.size()


func available_count() -> int:
	return _available.size()


func clear() -> void:
	for node in _active:
		if is_instance_valid(node) and node.get_parent() != null:
			node.get_parent().remove_child(node)
	_active.clear()
	_available.clear()
