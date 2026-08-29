extends SceneTree


func _init() -> void:
	var passed := _test_spring_launch_and_cooldown()
	passed = _test_spring_rejects_unknown_peer_and_recharges() and passed
	passed = _test_camera_feedback_look_ahead_and_impulse_cap() and passed
	passed = _test_hero_visual_reveals_speed_streak_above_top_tier() and passed
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


## An invalid actor must not consume a launch; each valid peer recharges alone.
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
	if not streak.visible:
		_fail("speed streak must show above the 0.85 run ratio")
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


func _fail(message: String) -> void:
	push_error(message)
