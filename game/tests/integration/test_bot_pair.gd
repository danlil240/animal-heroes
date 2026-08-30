extends SceneTree

## Two-agent-player gameplay harness.
##
## Instantiates one cooperative level, then drives BOTH heroes (Riki the rabbit
## and Foxy the fox) through the real input pipeline used by the game:
##   - The local hero (rabbit) is driven via TouchControls._keyboard, exactly
##     like a keyboard player, and routed by TwoPlayerLevel.route_control_frames().
##   - The remote hero (fox) is driven via TwoPlayerLevel._remote_keys, exactly
##     like the desktop second-player mapping, and routed by
##     apply_remote_desktop_frame().
##
## This deliberately exercises the production code path - including the
## authoritative action loop that fires bubbles, plays SFX, and steps enemies -
## so that real bugs (signal double-connects, pool exhaustion, runtime errors)
## surface during simulated two-player gameplay.
##
## Usage:
##   godot --headless --path game -s res://tests/integration/test_bot_pair.gd \
##       -- --level=sunny_forest --frames=1800
##
## Prints one structured BOT_REPORT line on stdout. Engine push_error / runtime
## errors are emitted on stderr and captured by the shell wrapper.

const TARGET_GROUPS: Array[String] = ["collectible", "bubble_powerup", "enemy"]
const DEFAULT_FRAMES: int = 1800  # 60s at 30 physics fps

var _level_id: String = ""
var _frames: int = DEFAULT_FRAMES


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_level_id = _argument_value("level")
	var frames_arg := _argument_value("frames")
	if not frames_arg.is_empty() and frames_arg.is_valid_int():
		_frames = maxi(int(frames_arg), 1)
	if _level_id.is_empty():
		# Auto-discovered by scripts/test_all.sh with no args: no-op so the
		# canonical gate stays green. The harness is a tool, not a regression
		# test; real runs pass --level=<id> via scripts/run_bot_pair.sh.
		print("BOT_REPORT skipped=true reason=no_level_arg")
		quit(0)
		return

	var scene_path := "res://levels/%s.tscn" % _level_id
	var packed: PackedScene = load(scene_path)
	if packed == null:
		_fail("level scene not found: %s" % scene_path)
		return
	var level: Node = packed.instantiate()
	root.add_child(level)
	# Let _ready + one physics tick settle so @onready vars and bodies initialize.
	await process_frame
	await physics_frame

	var rabbit: Node2D = level.get_node_or_null("Rabbit")
	var fox: Node2D = level.get_node_or_null("Fox")
	if rabbit == null or fox == null:
		_fail("level must define Rabbit and Fox heroes")
		return
	var touch_controls = level.get_node_or_null("HUD/TouchControls")
	if touch_controls == null:
		_fail("level must include HUD/TouchControls")
		return

	# Default local_role is rabbit; fox is the desktop-remote second player.
	# Ensure both heroes simulate locally (no network session is present).
	rabbit.is_network_remote = false
	fox.is_network_remote = false

	var rabbit_bot := BotState.new(1)
	var fox_bot := BotState.new(2)

	# Periodic bubble grants so the firing/SFX path is actually exercised.
	# In a real game these come from the bubble-flower powerup; we simulate the
	# pickup on a cadence to stress the projectile pool and audio voices.
	var grant_interval: int = 360  # ~12s
	var grant_timer: int = 30      # first grant quickly so firing starts early
	var grants_made: int = 0
	var can_grant: bool = level.has_method("grant_bubbles")

	var max_active_bubbles: int = 0
	var min_hearts_rabbit: int = rabbit.hearts
	var min_hearts_fox: int = fox.hearts
	var frames_run: int = 0
	var finished: bool = false

	for i in _frames:
		if not is_instance_valid(level):
			_fail("level instance destroyed mid-run")
			return
		if level.is_finished():
			finished = true
			break

		# Refresh bubble ammo on a cadence (simulates powerup pickup).
		if can_grant:
			grant_timer -= 1
			if grant_timer <= 0:
				grant_timer = grant_interval
				level.grant_bubbles(1)
				level.grant_bubbles(2)
				grants_made += 1

		# Choose targets through the real interactable/collectible groups.
		var rabbit_target := _pick_target(level, rabbit)
		var fox_target := _pick_target(level, fox)

		# Drive the local hero (rabbit) via the touch-controls keyboard state.
		_apply_to_touch_keyboard(touch_controls,
				_compute_bot_frame(rabbit, rabbit_target, rabbit_bot))
		# Drive the remote hero (fox) via the desktop second-player key state.
		_apply_to_remote_keys(level,
				_compute_bot_frame(fox, fox_target, fox_bot))

		await physics_frame
		frames_run = i + 1

		# Sample metrics after the physics step.
		if is_instance_valid(rabbit):
			min_hearts_rabbit = mini(min_hearts_rabbit, rabbit.hearts)
		if is_instance_valid(fox):
			min_hearts_fox = mini(min_hearts_fox, fox.hearts)
		var active: int = level.get_tree().get_nodes_in_group("active_bubble").size()
		max_active_bubbles = maxi(max_active_bubbles, active)

	var team_score: int = 0
	var stars_collected: int = 0
	if level.get("team_score") != null:
		team_score = int(level.team_score.total)
	if level.get("_collected_stars") != null:
		stars_collected = int(level._collected_stars)
	var enemies_remaining: int = level.get_tree().get_nodes_in_group("enemy").size()
	var pool_exhausted: bool = bool(level.get("_pool_exhaustion_reported")) if level.get("_pool_exhaustion_reported") != null else false
	var active_bubbles_now: int = level.get_tree().get_nodes_in_group("active_bubble").size()
	var rabbit_pos: Vector2 = rabbit.global_position if is_instance_valid(rabbit) else Vector2.ZERO
	var fox_pos: Vector2 = fox.global_position if is_instance_valid(fox) else Vector2.ZERO
	finished = finished or level.is_finished()

	# Compact, parse-friendly single-line report. The wrapper aggregates these.
	print("BOT_REPORT level=%s frames_run=%d frames_requested=%d finished=%s team_score=%d stars=%d enemies_remaining=%d hearts_rabbit=%d hearts_fox=%d min_hearts_rabbit=%d min_hearts_fox=%d grants=%d max_active_bubbles=%d active_bubbles=%d pool_exhausted=%s rabbit_pos=(%d,%d) fox_pos=(%d,%d)" % [
		_level_id, frames_run, _frames, str(finished).to_lower(),
		team_score, stars_collected, enemies_remaining,
		rabbit.hearts if is_instance_valid(rabbit) else -1,
		fox.hearts if is_instance_valid(fox) else -1,
		min_hearts_rabbit, min_hearts_fox,
		grants_made, max_active_bubbles, active_bubbles_now,
		str(pool_exhausted).to_lower(),
		int(rabbit_pos.x), int(rabbit_pos.y), int(fox_pos.x), int(fox_pos.y),
	])

	level.queue_free()
	await process_frame
	quit(0)


## Picks the nearest valid Node2D target from the gameplay groups, falling back
## to a level-specific finish anchor (Exit / BossEntrance) if the level is empty.
func _pick_target(level: Node, hero: Node2D) -> Node2D:
	if not is_instance_valid(hero):
		return null
	var best: Node2D = null
	var best_dist_sq: float = INF
	for group in TARGET_GROUPS:
		for candidate in level.get_tree().get_nodes_in_group(group):
			if not candidate is Node2D or not is_instance_valid(candidate):
				continue
			if candidate.is_queued_for_deletion():
				continue
			var dist_sq := hero.global_position.distance_squared_to(candidate.global_position)
			if dist_sq < best_dist_sq:
				best_dist_sq = dist_sq
				best = candidate
	if best != null:
		return best
	# Finish anchors keep the bots progressing toward the level exit.
	for anchor_name in ["Exit", "BossEntrance", "MagicalTreeFinish"]:
		var anchor = level.get_node_or_null(anchor_name)
		if anchor is Node2D and is_instance_valid(anchor):
			return anchor
	return null


## Pure bot "AI": produces a {left,right,jump,action} frame from hero state and
## a target. Stateless I/O is kept in BotState so the function is testable.
func _compute_bot_frame(hero: Node2D, target: Node2D, state: BotState) -> Dictionary:
	var frame := {"left": false, "right": false, "jump": false, "action": false}
	if not is_instance_valid(hero):
		return frame
	var on_floor: bool = bool(hero.is_on_floor())
	var pos: Vector2 = hero.global_position
	var vel: Vector2 = hero.velocity

	# Horizontal intent: chase the target, else wander.
	var dir: float = 0.0
	if target != null and is_instance_valid(target):
		var dx := target.global_position.x - pos.x
		if absf(dx) > 10.0:
			dir = signf(dx)
	else:
		state.wander_timer -= 1
		if state.wander_timer <= 0:
			state.wander_dir = -state.wander_dir if state.wander_dir != 0.0 else 1.0
			state.wander_timer = 90  # ~3s
		dir = state.wander_dir
	frame["left"] = dir < 0.0
	frame["right"] = dir > 0.0

	# Stuck detection: pressing into something that isn't moving.
	if absf(dir) > 0.0 and absf(vel.x) < 14.0 and on_floor:
		state.stuck_time += 1
	else:
		state.stuck_time = 0

	# Jump logic: periodic hops, unstuck hops, or chasing a target above us.
	state.periodic_jump -= 1
	state.jump_cooldown -= 1
	var target_above: bool = target != null and is_instance_valid(target) and target.global_position.y < pos.y - 48.0
	if on_floor and state.jump_cooldown <= 0 and (state.stuck_time > 8 or target_above or state.periodic_jump <= 0):
		frame["jump"] = true
		state.jump_cooldown = 18       # ~0.6s between jumps
		state.periodic_jump = 45       # ~1.5s periodic hop cadence

	# Action: pulse hold/release so the rising-edge AND held-fire paths both run.
	# In Sunny Forest this fires bubble fans (exercising the pool + SFX voices);
	# elsewhere it triggers interactables when in range.
	state.action_timer -= 1
	if state.action_timer <= 0:
		state.action_hold = not state.action_hold
		state.action_timer = 10 if state.action_hold else 16
	frame["action"] = state.action_hold

	return frame


func _apply_to_touch_keyboard(touch_controls: Node, frame: Dictionary) -> void:
	# TouchControls._keyboard is the desktop fallback state read by input_frame().
	# Driving it directly exercises the same path a keyboard player uses.
	touch_controls._keyboard["left"] = bool(frame["left"])
	touch_controls._keyboard["right"] = bool(frame["right"])
	touch_controls._keyboard["jump"] = bool(frame["jump"])
	touch_controls._keyboard["action"] = bool(frame["action"])


func _apply_to_remote_keys(level: Node, frame: Dictionary) -> void:
	# TwoPlayerLevel._remote_keys feeds _desktop_remote_frame() -> the partner
	# hero when no network peer is connected (offline / same-device two-player).
	level._remote_keys["left"] = bool(frame["left"])
	level._remote_keys["right"] = bool(frame["right"])
	level._remote_keys["jump"] = bool(frame["jump"])
	level._remote_keys["action"] = bool(frame["action"])


func _argument_value(name: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--%s=" % name):
			return argument.trim_prefix("--%s=" % name)
	return ""


func _fail(message: String) -> void:
	push_error("BOT_HARNESS_ERROR: %s" % message)
	print("BOT_REPORT level=%s error=%s" % [_level_id, message.replace(" ", "_")])
	quit(1)


class BotState:
	var peer_id: int
	var wander_dir: float = 1.0
	var wander_timer: int = 90
	var stuck_time: int = 0
	var jump_cooldown: int = 0
	var periodic_jump: int = 45
	var action_hold: bool = false
	var action_timer: int = 0

	func _init(p_peer_id: int) -> void:
		peer_id = p_peer_id
