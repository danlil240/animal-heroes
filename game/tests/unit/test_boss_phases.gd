extends SceneTree


func _init() -> void:
	var boss_script = load("res://world/robot_boss.gd")
	if boss_script == null:
		_fail("robot boss script must exist")
		return
	var boss = boss_script.new()
	boss.begin(true)
	if boss.phase != boss.AVOID:
		_fail("boss must start in AVOID after intro, got %s" % boss.phase)
		return
	# Three cycles of: activate both switches, hit both weak points.
	for cycle in 3:
		boss.activate_switch(1)
		boss.activate_switch(2)
		boss.hit_weak_point(1)
		boss.hit_weak_point(2)
	if boss.phase != boss.DEFEATED:
		_fail("boss must be DEFEATED after three complete cycles, got %s" % boss.phase)
		return
	if boss.defeat_emissions != 1:
		_fail("boss must emit defeat exactly once, got %d" % boss.defeat_emissions)
		return
	# Defeated boss ignores further input.
	boss.activate_switch(1)
	boss.hit_weak_point(1)
	if boss.phase != boss.DEFEATED:
		_fail("defeated boss must not change phase")
		return
	# Reset and re-run to verify determinism.
	boss.reset()
	boss.begin(true)
	for cycle in 3:
		boss.activate_switch(1)
		boss.activate_switch(2)
		boss.hit_weak_point(1)
		boss.hit_weak_point(2)
	if boss.phase != boss.DEFEATED or boss.defeat_emissions != 1:
		_fail("boss must be deterministic across resets")
		return
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
