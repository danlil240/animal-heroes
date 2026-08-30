class_name SunnyForest
extends CoopLevel

## Cooperative level 1: teaches movement, stomping, the bubble power-up, and the
## partner switch that opens the shared exit.

const TeamworkGateScript := preload("res://world/teamwork_gate.gd")
const ObjectPoolScript := preload("res://world/object_pool.gd")
const BubbleProjectileScene := preload("res://world/bubble_projectile.tscn")
const ActionResolverScript := preload("res://player/action_resolver.gd")

const INTERACTION_DISTANCE: float = 96.0
const FIRE_INTERVAL: float = 0.20
const BASIC_SHOT_VELOCITY: float = 360.0
const SPREAD_VERTICAL_VELOCITIES: Array[float] = [-70.0, 0.0, 70.0]

@onready var exit_node: Area2D = $Exit

var _players_at_exit: Dictionary = {}
var _finish_peers: Dictionary = {}
var _gates: Dictionary = {}
var _bubble_pool: RefCounted = null
var _bubble_sequence: int = 0
var _offline_action_sequences: Dictionary = {1: 1000, 2: 1000}
var _action_resolver: RefCounted = null
var _previous_action_held: Dictionary = {1: false, 2: false}
var _fire_remaining: Dictionary = {1: 0.0, 2: 0.0}
var _interaction_claims: Dictionary = {}
var _pool_exhaustion_reported: bool = false
var _discovered_secrets: Dictionary = {}
var _secret_triggers: Dictionary = {}
var _brambles: Dictionary = {}


func _setup_coop_level() -> void:
	exit_node.body_entered.connect(_on_exit_body_entered)
	exit_node.body_exited.connect(_on_exit_body_exited)
	_action_resolver = ActionResolverScript.new()
	_bubble_pool = ObjectPoolScript.new()
	_bubble_pool.configure(BubbleProjectileScene, 6)
	_configure_gate("fallen-log", ["log", "overhead-switch"])
	_configure_gate("bubble-grove", ["left-flower", "right-flower"])
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if enemy.has_signal("defeated"):
			enemy.defeated.connect(_on_enemy_defeated)
		if enemy.has_signal("player_hit"):
			enemy.player_hit.connect(_on_enemy_player_hit)
	for trigger in get_tree().get_nodes_in_group("secret"):
		if trigger.has_signal("discovered") and trigger.has_method("snapshot_state"):
			var sid := String(trigger.get("secret_id"))
			if not sid.is_empty():
				_secret_triggers[sid] = trigger
				trigger.discovered.connect(_on_secret_discovered)
	for bramble in get_tree().get_nodes_in_group("bramble"):
		if bramble.has_signal("broken") and bramble.has_method("snapshot_state"):
			var bid := String(bramble.get("bramble_id"))
			if not bid.is_empty():
				_brambles[bid] = bramble


func _step_level(delta: float) -> void:
	if _is_world_authority():
		for enemy in get_tree().get_nodes_in_group("enemy"):
			if enemy.has_method("host_step"):
				enemy.host_step(delta)
		for bubble in get_tree().get_nodes_in_group("active_bubble"):
			if bubble.has_method("host_step"):
				bubble.host_step(delta)
		_step_authoritative_actions(delta)
	for hero in [rabbit, fox]:
		hero.consume_action()
	_render_gameplay_hud()


func _present_level(_delta: float) -> void:
	var hud = get_node_or_null("HUD/GameplayHud")
	if hud == null:
		return
	var hero: Node2D = _local_hero()
	var target = _action_resolver.select(hero, get_tree().get_nodes_in_group("sunny_interactable"), INTERACTION_DISTANCE)
	if target != null:
		hud.show_context(String(target.interaction_kind))
	else:
		hud.show_context("bubble")


func register_enemy_defeat(enemy_id: String, _peer_id: int, score_payload: Dictionary = {}) -> bool:
	var event_id := "enemy:%s" % enemy_id
	var points: int = _award_authoritative_score(event_id, "enemy", score_payload) if not score_payload.is_empty() else _award_combo_score(event_id, "enemy")
	if points <= 0:
		return false
	AudioDirector.play_gameplay_cue("enemy_defeat", _peer_id)
	_show_score_gain(points, Vector2.ZERO)
	_render_gameplay_hud()
	return true


func activate_teamwork_part(gate_id: String, part_id: String, peer_id: int, score_payload: Dictionary = {}) -> bool:
	if not _gates.has(gate_id):
		return false
	var gate = _gates[gate_id]
	if gate_id == "bubble-grove" and gate.snapshot().get("active_parts", {}).values().has(peer_id):
		return false
	var before: Dictionary = gate.snapshot()
	var completed: bool = gate.mark_part(part_id, peer_id)
	if gate.snapshot() == before:
		return false
	var event_id := "gate:%s" % gate_id
	var points: int = _award_authoritative_score(event_id, "teamwork", score_payload) if not score_payload.is_empty() else _award_teamwork_score(event_id)
	if points > 0:
		AudioDirector.play_gameplay_cue("teamwork")
		_show_score_gain(points, Vector2.ZERO)
	if completed:
		_open_gate_barrier(gate_id)
	_render_gameplay_hud()
	return completed


func gate_is_open(gate_id: String) -> bool:
	return _gates.has(gate_id) and _gates[gate_id].is_complete()


func discover_secret(secret_id: String, peer_id: int, score_payload: Dictionary = {}) -> bool:
	if secret_id.is_empty() or (peer_id != 1 and peer_id != 2):
		return false
	if _discovered_secrets.has(secret_id):
		return false
	_discovered_secrets[secret_id] = true
	var event_id := "secret:%s" % secret_id
	var points: int = _award_authoritative_score(event_id, "secret", score_payload) if not score_payload.is_empty() else _award_combo_score(event_id, "secret")
	if points <= 0:
		_discovered_secrets.erase(secret_id)
		return false
	AudioDirector.play_gameplay_cue("secret", peer_id)
	_show_score_gain(points, Vector2.ZERO)
	_render_gameplay_hud()
	return true


func discovered_secret_count() -> int:
	return _discovered_secrets.size()


func secrets_total() -> int:
	return _secret_triggers.size()


func _completion_payload_extras() -> Dictionary:
	return {
		"secrets_found": discovered_secret_count(),
		"secrets_total": secrets_total(),
	}


func _render_gameplay_hud() -> void:
	var hud = get_node_or_null("HUD/GameplayHud")
	if hud == null or not hud.has_method("render"):
		return
	var local_peer_id := int(_local_hero().get("peer_id"))
	hud.render(
		team_score.total,
		rabbit.hearts,
		fox.hearts,
		bubble_ammo.remaining(local_peer_id),
		team_combo.multiplier,
		discovered_secret_count(),
		secrets_total(),
	)


func grant_bubbles(peer_id: int) -> int:
	var amount: int = bubble_ammo.grant(peer_id)
	_render_gameplay_hud()
	return amount


func fire_bubble(peer_id: int, origin: Vector2, direction: float) -> bool:
	if peer_id not in [1, 2] or absf(direction) < 0.001:
		return false
	var kind: String = bubble_ammo.kind(peer_id)
	var fan_velocities: Array = SPREAD_VERTICAL_VELOCITIES if kind == BubbleInventoryScript.SPREAD else [0.0]
	var acquired: Array[Node] = []
	for _vertical_velocity in fan_velocities:
		var bubble = _bubble_pool.acquire()
		if bubble == null:
			for partial in acquired:
				_bubble_pool.release(partial)
			_report_pool_exhaustion_once()
			return false
		acquired.append(bubble)
	_bubble_sequence += 1
	for index in acquired.size():
		var bubble = acquired[index]
		$Bubbles.add_child(bubble)
		bubble.add_to_group("active_bubble")
		if not bubble.released.is_connected(_on_bubble_released):
			bubble.released.connect(_on_bubble_released)
		if not bubble.enemy_hit.is_connected(_on_bubble_enemy_hit):
			bubble.enemy_hit.connect(_on_bubble_enemy_hit)
		var fan_index: int = index - 1 if kind == BubbleInventoryScript.SPREAD else 0
		var velocity := Vector2(signf(direction) * BASIC_SHOT_VELOCITY, fan_velocities[index])
		if not bubble.launch(peer_id, origin, velocity, _bubble_sequence, kind, fan_index):
			for member in acquired:
				member.remove_from_group("active_bubble")
				_bubble_pool.release(member)
			return false
	if kind == BubbleInventoryScript.SPREAD and not bubble_ammo.consume_spread(peer_id):
		for member in acquired:
			member.remove_from_group("active_bubble")
			_bubble_pool.release(member)
		return false
	AudioDirector.play_gameplay_cue("bubble", peer_id)
	_render_gameplay_hud()
	return true


func active_bubble_count() -> int:
	return _bubble_pool.active_count() if _bubble_pool != null else 0


func enter_finish(peer_id: int) -> bool:
	if peer_id <= 0 or _finish_peers.has(peer_id) or is_finished():
		return false
	_finish_peers[peer_id] = true
	if not (_finish_peers.has(1) and _finish_peers.has(2)):
		return false
	AudioDirector.play_gameplay_cue("finish")
	for hero in [rabbit, fox]:
		var visual = hero.get_node_or_null("Visual")
		if visual != null and visual.has_method("play_celebration"):
			visual.play_celebration()
	var tree_visual = get_node_or_null("MagicalTreeRun/MagicalTree/Visual")
	if tree_visual != null and tree_visual.has_method("play_celebration"):
		tree_visual.play_celebration()
	coop_mode.complete_level()
	return true


func leave_finish(peer_id: int) -> void:
	if not is_finished():
		_finish_peers.erase(peer_id)


## Host-owned authoritative snapshot of every shared mutable world object, used
## to reconstruct level state after a reconnect. Contains score and combo,
## collected ids, the active checkpoint, both hero positions, enemy motion,
## gate state, bubble ammo, in-flight projectiles, and event sequencing.
func world_state_snapshot() -> Dictionary:
	var enemies: Array[Dictionary] = []
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if enemy is EnemyActor:
			enemies.append(enemy.snapshot_state())
	var gates: Dictionary = {}
	for gate_id in _gates:
		gates[gate_id] = _gates[gate_id].snapshot()
	var projectiles: Array[Dictionary] = []
	for bubble in get_tree().get_nodes_in_group("active_bubble"):
		if bubble is BubbleProjectile and bubble.active:
			projectiles.append({
				"projectile_id": String(bubble.projectile_id),
				"owner_peer_id": int(bubble.owner_peer_id),
				"position": bubble.position,
				"velocity": bubble.velocity,
				"projectile_kind": String(bubble.projectile_kind),
				"fan_index": int(bubble.fan_index),
				"remaining": bubble.lifetime_remaining(),
			})
	return {
		"score": team_score.total,
		"collected_ids": team_score.snapshot()["awarded_ids"],
		"combo": team_combo.snapshot(),
		"checkpoint_id": coop_mode.current_checkpoint_id,
		"heroes": {1: rabbit.global_position, 2: fox.global_position},
		"enemies": enemies,
		"gates": gates,
		"ammo": bubble_ammo.snapshot(),
		"projectiles": projectiles,
		"event_sequence": _last_applied_world_event_sequence,
	}


## Replaces shared world state from a prior `world_state_snapshot()`. Rejects
## snapshots taken after the level already finished. Restores score, ammo,
## gates, enemies, hero positions, checkpoint, event sequence, and in-flight
## projectiles exactly.
func restore_world_state(snapshot: Dictionary) -> bool:
	if is_finished():
		return false
	var score_data := {"total": int(snapshot.get("score", -1)), "awarded_ids": snapshot.get("collected_ids", [])}
	if not team_score.restore(score_data):
		return false
	if not team_combo.restore(snapshot.get("combo", {})):
		return false
	if not bubble_ammo.restore(snapshot.get("ammo", {})):
		return false
	var gates_data: Variant = snapshot.get("gates", null)
	if not gates_data is Dictionary:
		return false
	for gate_id in gates_data:
		if not _gates.has(gate_id) or not _gates[gate_id].restore(gates_data[gate_id]):
			return false
	if not _restore_enemy_state(snapshot.get("enemies", [])):
		return false
	var heroes_data: Variant = snapshot.get("heroes", null)
	if heroes_data is Dictionary:
		if heroes_data.has(1):
			rabbit.global_position = Vector2(heroes_data[1])
		if heroes_data.has(2):
			fox.global_position = Vector2(heroes_data[2])
	coop_mode.current_checkpoint_id = String(snapshot.get("checkpoint_id", ""))
	_last_applied_world_event_sequence = int(snapshot.get("event_sequence", _last_applied_world_event_sequence))
	if not _restore_projectiles(snapshot.get("projectiles", [])):
		return false
	_reset_all_action_authority()
	_render_gameplay_hud()
	return true


func _restore_enemy_state(enemies_data: Variant) -> bool:
	if not enemies_data is Array:
		return false
	var by_id: Dictionary = {}
	for entry in enemies_data:
		if entry is Dictionary:
			by_id[String(entry.get("enemy_id", ""))] = entry
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if enemy is EnemyActor and by_id.has(String(enemy.enemy_id)):
			if not enemy.restore_state(by_id[String(enemy.enemy_id)]):
				return false
	return true


func _restore_projectiles(projectiles: Array) -> bool:
	var active_bubbles: Array = []
	for bubble in get_tree().get_nodes_in_group("active_bubble"):
		if bubble is BubbleProjectile:
			active_bubbles.append(bubble)
	for bubble in active_bubbles:
		bubble.remove_from_group("active_bubble")
		_bubble_pool.release(bubble)
	for payload in projectiles:
		if not payload is Dictionary:
			return false
		var bubble = _bubble_pool.acquire()
		if bubble == null:
			return false
		$Bubbles.add_child(bubble)
		bubble.add_to_group("active_bubble")
		if not bubble.released.is_connected(_on_bubble_released):
			bubble.released.connect(_on_bubble_released)
		if not bubble.enemy_hit.is_connected(_on_bubble_enemy_hit):
			bubble.enemy_hit.connect(_on_bubble_enemy_hit)
		if not bubble.restore_state(payload):
			bubble.remove_from_group("active_bubble")
			_bubble_pool.release(bubble)
			return false
	return true


func _validate_world_action(peer_id: int, action_id: String, target_id: String, hero_position: Vector2) -> Dictionary:
	var hero = rabbit if peer_id == 1 else fox if peer_id == 2 else null
	if hero == null or hero.global_position.distance_to(hero_position) > 24.0:
		return {}
	if action_id == "fire" and target_id == "bubble-shot":
		return {"kind": "bubble_fire", "payload": {
			"peer_id": peer_id,
			"origin": hero.global_position + Vector2(hero.facing_direction * 42.0, -10.0),
			"direction": hero.facing_direction,
		}}
	if action_id == "collect" and target_id.begins_with("star-"):
		var collectible := _star_node(target_id)
		if collectible != null and not collectible.is_queued_for_deletion() and hero.global_position.distance_to(collectible.global_position) <= INTERACTION_DISTANCE:
			return {"kind": "collect", "payload": {"target_id": target_id}}
		return {}
	var target := _interactable_node(target_id)
	if target == null or hero.global_position.distance_to(target.global_position) > INTERACTION_DISTANCE:
		return {}
	if target.has_method("eligible_for") and not target.eligible_for(hero):
		return {}
	match [action_id, target_id]:
		["push", "fallen-log"]:
			return {"kind": "gate_part", "payload": {"gate_id": "fallen-log", "part_id": "log", "peer_id": peer_id}}
		["switch", "overhead-switch"]:
			return {"kind": "gate_part", "payload": {"gate_id": "fallen-log", "part_id": "overhead-switch", "peer_id": peer_id}}
		["switch", "left-flower"], ["switch", "right-flower"]:
			return {"kind": "gate_part", "payload": {"gate_id": "bubble-grove", "part_id": target_id, "peer_id": peer_id}}
		["pickup", "bubble-flower"]:
			return {"kind": "bubble_grant", "payload": {"peer_id": peer_id}}
		["finish", "magical-tree"]:
			return {"kind": "finish", "payload": {"peer_id": peer_id}}
	return {}


func _prepare_world_event(kind: String, payload: Dictionary) -> Dictionary:
	match kind:
		"collect", "enemy_defeat", "secret_discovered":
			return _with_authoritative_combo_score(payload)
		"gate_part":
			return _with_authoritative_combo_score(payload, true)
	return payload.duplicate(true)


func _apply_world_event_accepted(_sequence: int, kind: String, payload: Dictionary) -> bool:
	match kind:
		"collect":
			var target_id := String(payload.get("target_id", ""))
			return collect_star(target_id, _star_node(target_id), payload)
		"gate_part":
			var gate_id := String(payload.get("gate_id", ""))
			if not _gates.has(gate_id):
				return false
			var before: Dictionary = _gates[gate_id].snapshot()
			activate_teamwork_part(gate_id, String(payload.get("part_id", "")), int(payload.get("peer_id", 0)), payload)
			return _gates[gate_id].snapshot() != before
		"bubble_grant":
			return grant_bubbles(int(payload.get("peer_id", 0))) > 0
		"bubble_fire":
			return fire_bubble(int(payload.get("peer_id", 0)), Vector2(payload.get("origin", Vector2.ZERO)), float(payload.get("direction", 0.0)))
		"enemy_defeat":
			return register_enemy_defeat(String(payload.get("enemy_id", "")), int(payload.get("peer_id", 0)), payload)
		"secret_discovered":
			return discover_secret(String(payload.get("secret_id", "")), int(payload.get("peer_id", 0)), payload)
		"finish":
			var before_count := _finish_peers.size()
			var was_finished := is_finished()
			enter_finish(int(payload.get("peer_id", 0)))
			return _finish_peers.size() != before_count or is_finished() != was_finished
	return false


func _on_collectible_entered(body: Node2D, collectible: Area2D) -> void:
	if not body.has_method("respawn") or collectible.is_queued_for_deletion():
		return
	if _has_live_world_peer() and body != _local_hero():
		return
	_submit_action(body, "collect", _collectible_id(collectible))


func _on_exit_body_entered(body: Node2D) -> void:
	if not body.has_method("respawn"):
		return
	_players_at_exit[body.get_instance_id()] = true
	enter_finish(int(body.get("peer_id")))


func _on_exit_body_exited(body: Node2D) -> void:
	if not body.has_method("respawn"):
		return
	_players_at_exit.erase(body.get_instance_id())
	leave_finish(int(body.get("peer_id")))


func _configure_gate(gate_id: String, parts: Array) -> void:
	var gate = TeamworkGateScript.new()
	gate.configure(gate_id, parts)
	_gates[gate_id] = gate


func _open_gate_barrier(gate_id: String) -> void:
	var path := "FallenLogCrossing/GateBarrier" if gate_id == "fallen-log" else "BubbleGrove/GateBarrier"
	var barrier := get_node_or_null(path)
	if barrier == null:
		return
	barrier.visible = false
	barrier.process_mode = Node.PROCESS_MODE_DISABLED
	var shape := barrier.get_node_or_null("CollisionShape2D")
	if shape != null:
		shape.set_deferred("disabled", true)


func _on_enemy_defeated(enemy_id: String, peer_id: int) -> void:
	if _is_world_authority():
		publish_world_event("enemy_defeat", {"enemy_id": enemy_id, "peer_id": peer_id})


func _on_secret_discovered(secret_id: String, peer_id: int) -> void:
	if _is_world_authority():
		publish_world_event("secret_discovered", {"secret_id": secret_id, "peer_id": peer_id})


func _on_enemy_player_hit(_enemy_id: String, peer_id: int) -> void:
	AudioDirector.play_gameplay_cue("damage", peer_id)
	_render_gameplay_hud()


func _on_bubble_enemy_hit(enemy_id: String, peer_id: int, _projectile_id: String) -> void:
	AudioDirector.play_gameplay_cue("enemy_hit", peer_id)


func _on_bubble_released(bubble: Node) -> void:
	bubble.remove_from_group("active_bubble")
	_bubble_pool.release(bubble)


func _step_authoritative_actions(delta: float) -> void:
	for hero in [rabbit, fox]:
		_step_hero_action(hero, delta)


func _step_hero_action(hero: Node2D, delta: float) -> void:
	var peer_id := int(hero.get("peer_id"))
	var held: bool = not hero.controls_locked() and bool(hero.snapshot().action_pressed)
	var was_held := bool(_previous_action_held.get(peer_id, false))
	if not held:
		_reset_action_authority(peer_id)
		return
	if not was_held:
		_previous_action_held[peer_id] = true
		_fire_remaining[peer_id] = FIRE_INTERVAL
		var target = _action_resolver.select(hero, get_tree().get_nodes_in_group("sunny_interactable"), INTERACTION_DISTANCE)
		if target != null:
			_interaction_claims[peer_id] = true
			_publish_hero_action(hero, String(target.interaction_kind), String(target.interactable_id))
			return
		_publish_hero_action(hero, "fire", "bubble-shot")
		return
	if _interaction_claims.has(peer_id):
		return
	var next_remaining := float(_fire_remaining.get(peer_id, FIRE_INTERVAL)) - maxf(delta, 0.0)
	while next_remaining <= 0.0:
		_publish_hero_action(hero, "fire", "bubble-shot")
		next_remaining += FIRE_INTERVAL
	_fire_remaining[peer_id] = next_remaining


func _publish_hero_action(hero: Node2D, action_id: String, target_id: String) -> bool:
	var peer_id := int(hero.get("peer_id"))
	var event: Dictionary = _validate_world_action(peer_id, action_id, target_id, hero.global_position)
	var kind := String(event.get("kind", ""))
	var payload: Variant = event.get("payload", null)
	if kind.is_empty() or not payload is Dictionary:
		return false
	return publish_world_event(kind, payload)


func _reset_world_input_state(peer_id: int) -> void:
	if peer_id <= 0:
		_reset_all_action_authority()
	else:
		_reset_action_authority(peer_id)


func _reset_action_authority(peer_id: int) -> void:
	_previous_action_held[peer_id] = false
	_fire_remaining[peer_id] = 0.0
	_interaction_claims.erase(peer_id)


func _reset_all_action_authority() -> void:
	_reset_action_authority(1)
	_reset_action_authority(2)


func _report_pool_exhaustion_once() -> void:
	if _pool_exhaustion_reported:
		return
	_pool_exhaustion_reported = true
	print_debug("Sunny Forest bubble pool exhausted; shot sequence rejected")


func _submit_action(hero: Node2D, action_id: String, target_id: String) -> void:
	if _has_live_world_peer():
		if hero == _local_hero():
			request_world_action(action_id, target_id, hero.global_position)
		return
	var peer_id := int(hero.get("peer_id"))
	_offline_action_sequences[peer_id] = int(_offline_action_sequences.get(peer_id, 1000)) + 1
	process_world_action(peer_id, int(_offline_action_sequences[peer_id]), action_id, target_id, hero.global_position)


func _interactable_node(target_id: String) -> Node2D:
	for target in get_tree().get_nodes_in_group("sunny_interactable"):
		if String(target.get("interactable_id")) == target_id:
			return target
	return null


func _star_node(target_id: String) -> Area2D:
	var suffix := target_id.trim_prefix("star-")
	return get_node_or_null("Collectibles/Star%s" % suffix) as Area2D
