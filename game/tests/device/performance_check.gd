extends SceneTree

# Headless performance capture for entity budgets and frame-time sampling.
# Physical device FPS gating is performed by scripts/device_smoke.sh on
# the SM-T220 tablets. This test verifies the worst-case scene stays within
# entity budgets and processes without errors.

const CLOUD_FACTORY_SCENE := "res://levels/cloud_factory.tscn"
const SUNNY_FOREST_SCENE := "res://levels/sunny_forest.tscn"
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
	# Cloud Factory remains the worst-case scene for entity density.
	if not await _validate_scene(CLOUD_FACTORY_SCENE):
		return
	# Sunny Forest must also stay within the shared campaign budgets after
	# the re-authoring and secret/bramble additions.
	if not await _validate_scene(SUNNY_FOREST_SCENE):
		return
	quit(0)


func _validate_scene(scene_path: String) -> bool:
	var scene := load(scene_path)
	if scene == null:
		_fail("%s scene must load for performance capture" % scene_path)
		return false
	_level = scene.instantiate()
	root.add_child(_level)
	await process_frame
	if not _validate_budgets():
		_cleanup()
		return false
	_elapsed = 0.0
	_frame_count = 0
	while _elapsed < SAMPLE_DURATION:
		await process_frame
		_elapsed += root.get_process_delta_time()
		_frame_count += 1
	if _frame_count < int(SAMPLE_DURATION * 20.0):
		_fail("performance capture produced too few frames for %s: %d" % [scene_path, _frame_count])
		_cleanup()
		return false
	_cleanup()
	return true

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
