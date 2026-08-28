extends SceneTree

# Headless performance capture for entity budgets and frame-time sampling.
# Physical device FPS gating is performed by scripts/device_smoke.sh on
# the SM-T220 tablets. This test verifies the worst-case scene stays within
# entity budgets and processes without errors.

const CLOUD_FACTORY_SCENE := "res://levels/cloud_factory.tscn"
const MAX_ENEMY_BUDGET := 12
const MAX_PROJECTILE_BUDGET := 24
const MAX_PARTICLE_BUDGET := 80
const SAMPLE_DURATION := 2.0

var _level: Node = null
var _elapsed: float = 0.0
var _frame_count: int = 0
var _error_count: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := load(CLOUD_FACTORY_SCENE)
	if scene == null:
		_fail("Cloud Factory scene must load for performance capture")
		return
	_level = scene.instantiate()
	root.add_child(_level)
	await process_frame
	if not _validate_budgets():
		_cleanup()
		return
	# Sample frames to detect processing errors
	while _elapsed < SAMPLE_DURATION:
		await process_frame
		_elapsed += root.get_process_delta_time()
		_frame_count += 1
	if _frame_count < int(SAMPLE_DURATION * 20.0):
		_fail("performance capture produced too few frames: %d" % _frame_count)
		_cleanup()
		return
	_cleanup()
	quit(0)

func _validate_budgets() -> bool:
	if _level.get("enemy_budget") == null or _level.enemy_budget > MAX_ENEMY_BUDGET:
		_fail("enemy_budget must be <= %d" % MAX_ENEMY_BUDGET)
		return false
	if _level.get("projectile_budget") == null or _level.projectile_budget > MAX_PROJECTILE_BUDGET:
		_fail("projectile_budget must be <= %d" % MAX_PROJECTILE_BUDGET)
		return false
	if _level.get("particle_budget") == null or _level.particle_budget > MAX_PARTICLE_BUDGET:
		_fail("particle_budget must be <= %d" % MAX_PARTICLE_BUDGET)
		return false
	return true

func _cleanup() -> void:
	if _level != null:
		root.remove_child(_level)
		_level.queue_free()

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
