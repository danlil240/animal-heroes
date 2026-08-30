class_name CoopLevel
extends TwoPlayerLevel

## Shared scaffolding for the cooperative campaign levels: the CoopMode rules
## object, confirmed checkpoints shared by both heroes, and the completion
## payload the app shell needs in order to unlock and open the next level.

const CoopModeScript := preload("res://modes/coop_mode.gd")
const TeamScoreScript := preload("res://core/team_score.gd")
const TeamComboScript := preload("res://core/team_combo.gd")
const BubbleInventoryScript := preload("res://player/bubble_inventory.gd")

## Campaign identifier for this level; set on the scene root.
@export var level_id: String = ""

var coop_mode: RefCounted = null
var team_score: RefCounted = null
var team_combo: RefCounted = null
var bubble_ammo: RefCounted = null
var _collected_stars: int = 0


func _setup_level() -> void:
	if level_id.is_empty():
		push_error("cooperative level must declare level_id")
	coop_mode = CoopModeScript.new()
	team_score = TeamScoreScript.new()
	team_combo = TeamComboScript.new()
	bubble_ammo = BubbleInventoryScript.new()
	rabbit.peer_id = 1
	fox.peer_id = 2
	coop_mode.start(level_id, levels_unlocked_through(level_id))
	coop_mode.level_completed.connect(_on_coop_level_completed)
	coop_mode.campaign_completed.connect(_on_coop_campaign_completed)
	for checkpoint in get_tree().get_nodes_in_group("checkpoint"):
		if checkpoint.has_signal("activated"):
			checkpoint.activated.connect(_on_checkpoint_activated)
	for collectible in get_tree().get_nodes_in_group("collectible"):
		if collectible is Area2D and collectible.has_signal("body_entered"):
			collectible.body_entered.connect(_on_collectible_entered.bind(collectible))
	_setup_coop_level()
	_render_gameplay_hud()


func _setup_coop_level() -> void:
	pass


func _step_shared_level_rules(delta: float) -> void:
	team_combo.step(delta)


## Campaign levels up to and including `id`, in campaign order.
static func levels_unlocked_through(id: String) -> Array:
	var levels: Array = []
	for level in CoopModeScript.CAMPAIGN_LEVELS:
		levels.append(level)
		if level == id:
			break
	return levels


static func next_campaign_level(id: String) -> String:
	var index: int = CoopModeScript.CAMPAIGN_LEVELS.find(id)
	if index < 0 or index + 1 >= CoopModeScript.CAMPAIGN_LEVELS.size():
		return ""
	return CoopModeScript.CAMPAIGN_LEVELS[index + 1]


func _on_checkpoint_activated(checkpoint_id: String, _peer_id: int) -> void:
	coop_mode.confirm_checkpoint(checkpoint_id)
	AudioDirector.play_gameplay_cue("checkpoint")
	var checkpoint_position := _checkpoint_position(checkpoint_id)
	for hero in [rabbit, fox]:
		hero.checkpoint_position = checkpoint_position


func _on_collectible_entered(body: Node2D, collectible: Area2D) -> void:
	if not body.has_method("respawn"):
		return
	if collectible.is_queued_for_deletion():
		return
	collect_star(_collectible_id(collectible), collectible)


func collect_star(star_id: String, collectible: Node = null, score_payload: Dictionary = {}) -> bool:
	var event_id := "star:%s" % star_id
	var points: int = _award_authoritative_score(event_id, "star", score_payload) if not score_payload.is_empty() else _award_combo_score(event_id, "star")
	if points <= 0:
		return false
	_collected_stars += 1
	AudioDirector.play_gameplay_cue("star")
	if collectible != null and is_instance_valid(collectible):
		collectible.queue_free()
	_show_score_gain(points, collectible.global_position if collectible is Node2D else Vector2.ZERO)
	_render_gameplay_hud()
	return true


func _award_combo_score(event_id: String, category: String) -> int:
	var multiplier: int = team_combo.preview_multiplier()
	var points: int = team_score.award(event_id, category, multiplier)
	if points > 0:
		team_combo.commit_scored_event()
	return points


## Builds the immutable score outcome a host includes in a world event. The
## receiver applies these exact values instead of consulting its local timer.
func _with_authoritative_combo_score(payload: Dictionary, teamwork: bool = false) -> Dictionary:
	var result := payload.duplicate(true)
	var score_multiplier: int = 1 if teamwork else team_combo.preview_multiplier()
	var combo_state: Dictionary = team_combo.snapshot()
	if teamwork:
		if float(combo_state.get("remaining", 0.0)) > 0.0:
			combo_state["remaining"] = TeamComboScript.WINDOW
	else:
		combo_state = {
			"multiplier": score_multiplier,
			"remaining": TeamComboScript.WINDOW,
		}
	result["score_multiplier"] = score_multiplier
	result["combo_state"] = combo_state
	return result


## Applies a host-carried score and combo result. Validate the compact combo
## outcome before changing score; full rich restore atomicity remains Task 8.
func _award_authoritative_score(event_id: String, category: String, payload: Dictionary) -> int:
	var multiplier_value: Variant = payload.get("score_multiplier", null)
	var combo_value: Variant = payload.get("combo_state", null)
	if typeof(multiplier_value) != TYPE_INT or not combo_value is Dictionary:
		return 0
	var multiplier := int(multiplier_value)
	if multiplier < 1 or multiplier > TeamComboScript.MAX_MULTIPLIER:
		return 0
	var validated_combo = TeamComboScript.new()
	if not validated_combo.restore(combo_value):
		return 0
	var points: int = team_score.award(event_id, category, multiplier)
	if points > 0:
		team_combo.restore(combo_value)
	return points


func _award_teamwork_score(event_id: String) -> int:
	var points: int = team_score.award(event_id, "teamwork", 1)
	if points > 0:
		team_combo.refresh()
	return points


func _render_gameplay_hud() -> void:
	var hud = get_node_or_null("HUD/GameplayHud")
	if hud == null or not hud.has_method("render"):
		return
	var local_peer_id := int(_local_hero().get("peer_id"))
	hud.render(team_score.total, rabbit.hearts, fox.hearts, bubble_ammo.remaining(local_peer_id))


func _show_score_gain(points: int, world_position: Vector2) -> void:
	var hud = get_node_or_null("HUD/GameplayHud")
	if hud != null and hud.has_method("show_score_gain"):
		hud.show_score_gain(points, world_position)


func _collectible_id(collectible: Node) -> String:
	var raw_name := String(collectible.name)
	if raw_name.begins_with("Star") and raw_name.trim_prefix("Star").is_valid_int():
		return "star-%s" % raw_name.trim_prefix("Star")
	return raw_name.to_snake_case()


func _checkpoint_position(checkpoint_id: String) -> Vector2:
	for checkpoint in get_tree().get_nodes_in_group("checkpoint"):
		if checkpoint.get("checkpoint_id") == checkpoint_id:
			return checkpoint.global_position
	return rabbit.checkpoint_position


func _on_coop_level_completed(completed_level_id: String) -> void:
	var payload := {
		"mode": "coop",
		"level_id": completed_level_id,
		"next_level_id": next_campaign_level(completed_level_id),
		"unlocked_levels": coop_mode.unlocked_levels.duplicate(),
		"campaign_completed": coop_mode.is_campaign_completed(),
		"winner_peer_id": 0,
		"scores": {},
		"team_score": team_score.total,
		"stars_collected": _collected_stars,
	}
	payload.merge(_completion_payload_extras(), true)
	finish_level(payload)


## Override to add level-specific completion fields without changing the shared
## results-screen contract.
func _completion_payload_extras() -> Dictionary:
	return {}


func _on_coop_campaign_completed(unlocked_levels: Array) -> void:
	finish_level({
		"mode": "coop",
		"level_id": level_id,
		"next_level_id": "",
		"unlocked_levels": unlocked_levels.duplicate(),
		"campaign_completed": true,
		"winner_peer_id": 0,
		"scores": {},
		"team_score": team_score.total,
	})
