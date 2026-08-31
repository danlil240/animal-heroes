extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var passed := _test_spring_launch_and_cooldown()
	passed = _test_spring_rejects_unknown_peer_and_recharges() and passed
	var cooldown_driver_passed: bool = await _test_spring_cooldown_is_driven_by_level_physics()
	passed = cooldown_driver_passed and passed
	var camera_binding_passed: bool = await _test_rabbit_local_camera_receives_feedback_target()
	passed = camera_binding_passed and passed
	passed = _test_camera_feedback_look_ahead_and_impulse_cap() and passed
	passed = _test_hero_visual_reveals_speed_streak_above_top_tier() and passed
	passed = _test_secret_trigger_idempotency_and_restore() and passed
	passed = _test_coop_secret_requires_two_distinct_peers_within_window() and passed
	passed = _test_breakable_bramble_only_active_bubble_breaks_once() and passed
	quit(0 if passed else 1)


## A duplicate overlap must not repeatedly reset a player's launch velocity.
func _test_spring_launch_and_cooldown() -> bool:
	var spring_script = load("res://world/spring_pad.gd")
	if spring_script == null:
		_fail("spring pad script must exist")
		return false
	var spring = spring_script.new()
	spring.launch_velocity = Vector2(120.0, -720.0)
	var hero = load("res://player/player_body.gd").new()
	hero.peer_id = 1
	root.add_child(hero)
	if not spring.try_launch(hero):
		_fail("spring must accept a live player")
		return false
	if hero.velocity != Vector2(120.0, -720.0):
		_fail("spring must apply exact launch velocity")
		return false
	if spring.try_launch(hero):
		_fail("spring cooldown must reject an immediate duplicate")
		return false
	hero.free()
	spring.free()
	return true


## An invalid actor must not consume a launch; its local API can also be stepped directly.
func _test_spring_rejects_unknown_peer_and_recharges() -> bool:
	var spring_script = load("res://world/spring_pad.gd")
	if spring_script == null:
		_fail("spring pad script must exist")
		return false
	var spring = spring_script.new()
	var invalid_hero = load("res://player/player_body.gd").new()
	invalid_hero.peer_id = 3
	root.add_child(invalid_hero)
	if spring.try_launch(invalid_hero):
		_fail("spring must only launch the two known peers")
		return false
	var hero = load("res://player/player_body.gd").new()
	hero.peer_id = 2
	root.add_child(hero)
	if not spring.try_launch(hero):
		_fail("second known peer must launch")
		return false
	spring.host_step(0.25)
	if not spring.try_launch(hero):
		_fail("spring must accept a peer after its 0.25 second cooldown")
		return false
	invalid_hero.free()
	hero.free()
	spring.free()
	return true


## Placed springs must receive the level's fixed physics cadence without a scene-specific hook.
func _test_spring_cooldown_is_driven_by_level_physics() -> bool:
	var level_scene = load("res://levels/test_arena.tscn")
	var spring_script = load("res://world/spring_pad.gd")
	if level_scene == null or spring_script == null:
		_fail("test arena and spring script must exist")
		return false
	var level = level_scene.instantiate()
	var spring = spring_script.new()
	spring.position = Vector2(-500.0, -500.0)
	level.add_child(spring)
	root.add_child(level)
	await physics_frame
	level.rabbit.peer_id = 1
	if not spring.try_launch(level.rabbit):
		_fail("placed spring must launch the local hero")
		return false
	for _tick in 20:
		await physics_frame
	if not spring.try_launch(level.rabbit):
		_fail("level physics must expire a placed spring cooldown")
		return false
	level.free()
	return true


## The default rabbit-local role must bind an opted-in camera to its local hero.
func _test_rabbit_local_camera_receives_feedback_target() -> bool:
	var level_scene = load("res://levels/test_arena.tscn")
	var camera_script = load("res://visual/camera_feedback.gd")
	if level_scene == null or camera_script == null:
		_fail("test arena and camera feedback script must exist")
		return false
	var level = level_scene.instantiate()
	var camera = level.get_node_or_null("Rabbit/Camera2D")
	if camera == null:
		_fail("test arena rabbit camera must exist")
		return false
	camera.set_script(camera_script)
	root.add_child(level)
	await process_frame
	if camera._hero != level.rabbit:
		_fail("rabbit-local camera feedback must follow the rabbit")
		return false
	level.free()
	return true


## High velocity looks ahead by the specified exponential response; a shake stays bounded.
func _test_camera_feedback_look_ahead_and_impulse_cap() -> bool:
	var camera_script = load("res://visual/camera_feedback.gd")
	if camera_script == null:
		_fail("camera feedback script must exist")
		return false
	var camera = camera_script.new()
	var hero = load("res://player/player_body.gd").new()
	hero.velocity = Vector2(1000.0, 0.0)
	root.add_child(hero)
	root.add_child(camera)
	camera.set_follow_hero(hero)
	camera.advance_feedback(0.1)
	if not is_equal_approx(camera.position.x, 49.560):
		_fail("camera look-ahead must smooth toward the 90 pixel clamp")
		return false
	camera.add_impulse(30.0)
	camera.advance_feedback(0.0)
	if camera.position.y > 10.001:
		_fail("camera impulse must be capped at 10 pixels")
		return false
	camera.advance_feedback(0.1)
	if camera.position.y >= 10.0:
		_fail("camera shake must decay without accumulating into camera position")
		return false
	for _tick in 8:
		camera.advance_feedback(0.1)
	if absf(camera.position.y) > 0.1:
		_fail("camera shake must return to its base offset across multiple frames")
		return false
	hero.free()
	camera.free()
	return true


## The high-speed presentation must be attached to the hero instead of world UI.
func _test_hero_visual_reveals_speed_streak_above_top_tier() -> bool:
	var visual_scene = load("res://visual/hero_visual.tscn")
	if visual_scene == null:
		_fail("hero visual scene must exist")
		return false
	var hero = load("res://player/player_body.gd").new()
	hero.profile = load("res://player/rabbit_profile.tres")
	root.add_child(hero)
	var visual = visual_scene.instantiate()
	hero.add_child(visual)
	visual.configure("rabbit", hero)
	var streak := visual.get_node_or_null("Pose/SpeedStreak") as Sprite2D
	if streak == null:
		_fail("hero visual must include the speed streak")
		return false
	hero.velocity.x = hero.profile.max_run_speed * 0.86
	visual._process(0.0)
	if streak.visible:
		_fail("speed presentation must stay off until a level explicitly opts in")
		return false
	hero._just_landed = true
	visual._process(0.0)
	if visual._landing_squash_remaining > 0.0:
		_fail("landing squash must stay off until a level explicitly opts in")
		return false
	hero._just_landed = false
	visual._process(0.0)
	visual.speed_presentation_enabled = true
	visual._process(0.0)
	if not streak.visible:
		_fail("opted-in speed presentation must show above the 0.85 run ratio")
		return false
	hero._just_landed = true
	visual._process(0.0)
	if visual._landing_squash_remaining <= 0.0:
		_fail("landing state must begin a squash")
		return false
	visual._process(0.16)
	visual._process(0.1)
	if visual._landing_squash_remaining > 0.0:
		_fail("landing squash must trigger once for a sustained landing state")
		return false
	hero.remove_child(visual)
	visual.free()
	hero.free()
	return true


## A single-pad secret must discover once for a valid peer, reject a second
## discovery, and remain idempotent after a snapshot round trip.
func _test_secret_trigger_idempotency_and_restore() -> bool:
	var trigger_script = load("res://world/secret_trigger.gd")
	if trigger_script == null:
		_fail("secret trigger script must exist")
		return false
	var trigger = trigger_script.new()
	trigger.secret_id = "momentum-carrot"
	if not trigger.discover(1):
		_fail("first discovery must succeed")
		return false
	if trigger.discover(2):
		_fail("same secret must not discover twice")
		return false
	if trigger.discover(1):
		_fail("repeat discovery by the same peer must not re-discover")
		return false
	var restored = trigger_script.new()
	restored.secret_id = "momentum-carrot"
	if not restored.restore_state(trigger.snapshot_state()):
		_fail("restored discovery must restore from a valid snapshot")
		return false
	if restored.discover(1):
		_fail("restored discovery must remain idempotent")
		return false
	var mismatch = trigger_script.new()
	mismatch.secret_id = "combat-carrot"
	if mismatch.restore_state(trigger.snapshot_state()):
		_fail("restore must reject a snapshot whose secret id does not match")
		return false
	var empty = trigger_script.new()
	empty.secret_id = ""
	if empty.discover(1):
		_fail("a secret with an empty id must not discover")
		return false
	if empty.discover(3):
		_fail("a secret must only accept peer 1 or 2")
		return false
	trigger.free()
	restored.free()
	mismatch.free()
	empty.free()
	return true


## A co-op secret must require two distinct peers within the one-second window
## and reject a second activation from the same peer or a late second peer.
func _test_coop_secret_requires_two_distinct_peers_within_window() -> bool:
	var trigger_script = load("res://world/secret_trigger.gd")
	if trigger_script == null:
		_fail("secret trigger script must exist")
		return false
	var trigger = trigger_script.new()
	trigger.secret_id = "coop-carrot"
	trigger.coop_activation = true
	if trigger.discover(1):
		_fail("co-op secret must not complete on a single peer activation")
		return false
	if trigger.discover(1):
		_fail("co-op secret must reject a duplicate same-peer activation")
		return false
	if not trigger.discover(2):
		_fail("co-op secret must complete when the second distinct peer activates in time")
		return false
	if trigger.discover(1):
		_fail("completed co-op secret must remain idempotent")
		return false
	# A late second peer must not complete the secret.
	var late = trigger_script.new()
	late.secret_id = "coop-carrot-late"
	late.coop_activation = true
	late.discover(1)
	late.host_step(1.01)
	if late.discover(2):
		_fail("co-op secret must expire after the one-second window")
		return false
	trigger.free()
	late.free()
	return true


## A bramble must break only for an active basic or spread bubble, emit broken
## once, and reject repeat hits and non-bubble actors.
func _test_breakable_bramble_only_active_bubble_breaks_once() -> bool:
	var bramble_script = load("res://world/breakable_bramble.gd")
	if bramble_script == null:
		_fail("breakable bramble script must exist")
		return false
	var bramble = bramble_script.new()
	bramble.bramble_id = "grove-bramble"
	var bubble_script = load("res://world/bubble_projectile.gd")
	var bubble = bubble_script.new()
	bubble.active = true
	bubble.projectile_kind = "basic"
	var broken_counter := {"count": 0}
	bramble.broken.connect(func(_id: String, _peer: int) -> void: broken_counter["count"] += 1)
	if not bramble.try_projectile(bubble):
		_fail("an active basic bubble must break the bramble")
		return false
	if bramble.try_projectile(bubble):
		_fail("a repeat hit must not break the bramble again")
		return false
	if int(broken_counter["count"]) != 1:
		_fail("broken must emit exactly once")
		return false
	var spread = bubble_script.new()
	spread.active = true
	spread.projectile_kind = "spread"
	if bramble.try_projectile(spread):
		_fail("an already-broken bramble must reject a spread bubble")
		return false
	var inactive = bubble_script.new()
	inactive.active = false
	inactive.projectile_kind = "basic"
	var fresh = bramble_script.new()
	fresh.bramble_id = "fresh-bramble"
	if fresh.try_projectile(inactive):
		_fail("an inactive bubble must not break a bramble")
		return false
	var non_bubble = Node2D.new()
	if fresh.try_projectile(non_bubble):
		_fail("a non-bubble node must not break a bramble")
		return false
	bramble.free()
	bubble.free()
	spread.free()
	inactive.free()
	fresh.free()
	non_bubble.free()
	return true


func _fail(message: String) -> void:
	push_error(message)
