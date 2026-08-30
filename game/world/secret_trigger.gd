class_name SecretTrigger
extends Area2D

## An optional, one-time secret. Single-pad triggers complete on the first
## valid peer; co-op triggers require two distinct peers inside a one-second
## window. World owners connect `discovered` and route the award through their
## authoritative event path.

signal discovered(secret_id: String, peer_id: int)

const COOP_WINDOW: float = 1.0

@export var secret_id: String = ""
@export var coop_activation: bool = false

var _discovered: bool = false
var _coop_peers: Dictionary = {}
var _coop_armed: bool = false
var _coop_timer: float = 0.0
var _reveal_tween: Tween


func _ready() -> void:
	add_to_group("secret")
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func host_step(delta: float) -> void:
	if not coop_activation or not _coop_armed or _discovered:
		return
	_coop_timer = maxf(_coop_timer - maxf(delta, 0.0), 0.0)
	if _coop_timer <= 0.0:
		_coop_armed = false
		_coop_peers.clear()


func discover(peer_id: int) -> bool:
	if secret_id.is_empty() or (peer_id != 1 and peer_id != 2):
		return false
	if _discovered:
		return false
	if coop_activation:
		if _coop_peers.has(peer_id):
			return false
		_coop_peers[peer_id] = true
		_coop_armed = true
		_coop_timer = COOP_WINDOW
		if _coop_peers.size() >= 2:
			_complete(peer_id)
			return true
		return false
	_complete(peer_id)
	return true


func is_discovered() -> bool:
	return _discovered


func snapshot_state() -> Dictionary:
	return {
		"secret_id": secret_id,
		"discovered": _discovered,
	}


func restore_state(data: Dictionary) -> bool:
	if not data.has_all(["secret_id", "discovered"]):
		return false
	if typeof(data["secret_id"]) != TYPE_STRING or String(data["secret_id"]) != secret_id:
		return false
	if typeof(data["discovered"]) != TYPE_BOOL:
		return false
	_discovered = bool(data["discovered"])
	_coop_armed = false
	_coop_peers.clear()
	_coop_timer = 0.0
	if _discovered:
		set_deferred("monitoring", false)
	return true


func _complete(peer_id: int) -> void:
	_discovered = true
	set_deferred("monitoring", false)
	_play_reveal_animation()
	discovered.emit(secret_id, peer_id)


func _on_body_entered(body: Node) -> void:
	if not body is CharacterBody2D or not body.has_method("respawn"):
		return
	discover(int(body.get("peer_id")))


func _play_reveal_animation() -> void:
	var visual := get_node_or_null("Visual") as Node2D
	if visual == null:
		return
	if _reveal_tween != null:
		_reveal_tween.kill()
	visual.scale = Vector2(1.3, 1.3)
	visual.modulate.a = 1.0
	_reveal_tween = create_tween()
	_reveal_tween.tween_property(visual, "scale", Vector2(0.9, 0.9), 0.18)
	_reveal_tween.parallel().tween_property(visual, "modulate:a", 0.0, 0.4)
