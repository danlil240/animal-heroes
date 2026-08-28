class_name StarRaceArena
extends CompetitionArena

## Friendly race: four ordered checkpoints per route, per-peer respawn at the
## most recent race checkpoint, and a grace period for the second finisher.

const StarRaceModeScript := preload("res://modes/star_race_mode.gd")

@onready var finish_line = $FinishLine

var race_mode: RefCounted = null

var _host_tick: float = 0.0
var _peer_checkpoints: Dictionary = {}


func _setup_arena() -> void:
	race_mode = StarRaceModeScript.new()
	race_mode.start()
	race_mode.race_completed.connect(_finish_match)
	_peer_checkpoints[HOST_PEER_ID] = rabbit.global_position
	_peer_checkpoints[GUEST_PEER_ID] = fox.global_position
	finish_line.body_entered.connect(_on_finish_body_entered)
	for checkpoint in get_tree().get_nodes_in_group("race_checkpoint"):
		if checkpoint is Area2D:
			checkpoint.body_entered.connect(_on_checkpoint_body_entered.bind(checkpoint))


func _step_level(delta: float) -> void:
	_host_tick += delta
	race_mode.tick(delta, _host_tick)


func _on_checkpoint_body_entered(body: Node, checkpoint: Area2D) -> void:
	var peer_id := _peer_id_of(body)
	if peer_id == 0:
		return
	var checkpoint_id: String = checkpoint.get("checkpoint_id")
	if checkpoint_id.is_empty():
		return
	if race_mode.pass_checkpoint(peer_id, checkpoint_id, _host_tick):
		_peer_checkpoints[peer_id] = checkpoint.global_position


func _on_finish_body_entered(body: Node) -> void:
	var peer_id := _peer_id_of(body)
	if peer_id == 0:
		return
	race_mode.finish(peer_id, _host_tick)


func _respawn_fallen_hero(body: Node2D) -> void:
	var peer_id := _peer_id_of(body)
	if peer_id == 0:
		return
	body.respawn(_peer_checkpoints.get(peer_id, body.checkpoint_position))


func _peer_id_of(body: Node) -> int:
	if not body.has_method("respawn"):
		return 0
	return int(body.get_meta("peer_id", 0))
