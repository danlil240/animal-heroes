class_name SpringPad
extends Area2D

## A local traversal pad. World owners call host_step at the existing 30 Hz
## cadence, while overlap detection only requests an immediate launch.

signal launched(peer_id: int)

const COOLDOWN_SECONDS: float = 0.25

@export var launch_velocity: Vector2 = Vector2(0.0, -720.0)

var _cooldown_by_peer: Dictionary = {}
var _launch_tween: Tween


func _ready() -> void:
	add_to_group("spring_pad")
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func host_step(delta: float) -> void:
	var step := maxf(delta, 0.0)
	for peer in _cooldown_by_peer.keys():
		var remaining := maxf(float(_cooldown_by_peer[peer]) - step, 0.0)
		if remaining <= 0.0:
			_cooldown_by_peer.erase(peer)
		else:
			_cooldown_by_peer[peer] = remaining


func try_launch(body: Node) -> bool:
	if not body is CharacterBody2D:
		return false
	var peer_id := int(body.get("peer_id"))
	if peer_id != 1 and peer_id != 2:
		return false
	if float(_cooldown_by_peer.get(peer_id, 0.0)) > 0.0:
		return false
	(body as CharacterBody2D).velocity = launch_velocity
	_cooldown_by_peer[peer_id] = COOLDOWN_SECONDS
	launched.emit(peer_id)
	_play_launch_animation()
	return true


func _on_body_entered(body: Node) -> void:
	try_launch(body)


func _play_launch_animation() -> void:
	var visual := get_node_or_null("Visual") as Node2D
	if visual == null:
		return
	if _launch_tween != null:
		_launch_tween.kill()
	visual.scale = Vector2(1.18, 0.62)
	_launch_tween = create_tween()
	_launch_tween.tween_property(visual, "scale", Vector2(0.92, 1.12), 0.07)
	_launch_tween.tween_property(visual, "scale", Vector2.ONE, 0.12)
