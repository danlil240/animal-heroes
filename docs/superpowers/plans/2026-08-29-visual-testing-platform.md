# Visual Testing Platform Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A PC-based automated game testing platform that scripts both heroes' input, captures screenshots, detects bugs, compares against baselines, and emits an HTML report — without new dependencies or changes to existing game code.

**Architecture:** Three layers. (1) A GDScript `TestRunner` (extends `SceneTree`) that loads a level into a 1340×800 `SubViewport`, manually steps both heroes + the level frame-by-frame at 30fps, captures screenshots, evaluates assertions, and writes `result.json`. (2) A stdlib-only Python orchestrator that launches each test as a Godot process, scans process output for errors, compares screenshots against baselines via a hand-written PNG decoder, and generates an HTML report. (3) An interactive `LiveInspect` mode for manual debugging.

**Tech Stack:** Godot 4.7.2 (typed GDScript, gl_compatibility renderer, 30 physics ticks/s), Python 3.12 stdlib only (zlib for PNG decoding, string templating for HTML).

**Spec:** `docs/superpowers/specs/2026-08-29-visual-testing-platform-design.md`

## Global Constraints

- No new third-party dependencies (Godot + Python stdlib only). Never `pip install`.
- No changes to existing game code, autoloads, or `project.godot`.
- Visual tests are separate from the existing headless suite — must not break `bash scripts/test_all.sh`.
- Runs on this PC with `DISPLAY=:0` (Godot 4.7.2, gl_compatibility). Headless mode cannot capture screenshots.
- Screenshots captured via `SubViewport.get_texture().get_image().save_png()`.
- Input scripted via synthetic `InputFrame` objects (`axis`, `jump`, `action`), bypassing `TouchControls`.
- Both heroes scripted independently by peer_id (1=rabbit, 2=fox). Frame-based timing at 30fps.
- Verify before claiming success: run `bash scripts/test_all.sh` and the new visual test commands; paste real output.

## Resolved design decisions (from codebase exploration)

These are not in the spec but were required to make the harness work against the real game code. They are locked here so every task uses the same model.

1. **Simulation model — full manual control.** The level scene's `_physics_process` calls `_step_level` then `route_control_frames()` (which overwrites the local hero's input with empty touch input) then network sync. To script both heroes deterministically without modifying game code, the `TestRunner` adds the level to a `SubViewport`, then calls `level.set_physics_process(false)` and `level.set_process(false)` to stop automatic level hooks (no double-stepping, no touch-input overwrite, no network). Both heroes' `_physics_process` is also disabled (`hero.set_physics_process(false)`) and `physics_step(delta)` is called manually. Per frame: `hero.apply_input(frame)` for both → `hero.physics_step(delta)` for both → `level._step_level(delta)`. Enemies and bubbles have no `_physics_process` of their own — `EnemyActor` moves only via `host_step` called from `_step_level`, and `BubbleProjectile` likewise — so manually calling `_step_level` steps them correctly. `move_and_slide` is safe to call manually here because heroes only collide with static bodies (ground/platforms); enemy/bubble/collectible/exit interactions arrive via `Area2D.body_entered` signals, which still fire during the SceneTree's automatic physics ticks.
2. **World authority is offline.** `_is_world_authority()` returns `true` when there is no `Session` in `PLAYING` state (the Session autoload exists but is idle), and `_has_live_world_peer()` returns `false`. So `_step_level` runs enemy/bubble `host_step`, and `_submit_action` → `process_world_action` resolves actions locally. No network code runs.
3. **Error scanning lives in the orchestrator.** GDScript cannot hook `push_error`/`SCRIPT ERROR` from script. The `TestRunner` evaluates every assertion kind **except** `no_errors` in-process (it records `no_errors` assertions as `pass` provisionally with `"needs_log_scan": true`). The Python orchestrator captures the Godot process's combined stdout/stderr, scans for `ERROR`/`SCRIPT ERROR`/`push_error` lines, and if any are found it marks every `no_errors` assertion failed and adds an `error_log` array to `result.json`.
4. **Camera renders the game view.** The level's `_ready` calls `configure_local_role` which makes the rabbit camera current. Inside the `SubViewport` that camera is the active one, so screenshots show the live game view as the rabbit moves (camera limits 0..3200 × 0..800).
5. **PNG decoding** must handle Godot's output: 8-bit, color type 6 (RGBA), with all five filter rows (None/Sub/Up/Average/Paeth). The decoder unfilters scanlines into an RGBA byte buffer for pixel comparison and diff PNG generation.
6. **test_all.sh exclusion.** `scripts/test_all.sh` currently runs `find game/tests -name 'test_*.gd'` with `--headless`. The new `game/tests/platform/test_*.gd` files must be excluded (they need a display) and a new DISPLAY-gated visual-tests section added.

## File Structure

```
game/tests/platform/
├── input_timeline.gd          # InputTimeline: frame→input map, captures, assertions
├── test_runner.gd             # TestRunner (SceneTree): SubViewport, manual loop, result.json
├── live_inspect.gd            # Interactive debugging mode
├── test_sunny_forest_walk.gd  # Example: both heroes walk the meadow
├── test_sunny_forest_gates.gd # Example: open the fallen-log teamwork gate
└── test_sunny_forest_full.gd  # Example: stars, gate, bubbles, finish

game/tests/unit/
└── test_input_timeline.gd     # Headless logic test for InputTimeline (runs in test_all.sh)

scripts/
├── run_visual_tests.py        # Orchestrator: discover, launch, compare, report
└── compare_screenshots.py     # Stdlib PNG decode + pixel diff + diff PNG writer

test-output/                   # gitignored except baselines/
├── baselines/                 # committed via --update-baselines
├── <test_name>/
│   ├── result.json
│   └── *.png
└── report.html

docs/
└── visual-testing.md          # Operator-facing docs
```

---

### Task 1: InputTimeline + headless unit test

**Files:**
- Create: `game/tests/platform/input_timeline.gd`
- Create: `game/tests/unit/test_input_timeline.gd`

**Interfaces:**
- Produces: `InputTimeline` class with `add(peer_id, start_frame, end_frame, input)`, `capture(frame, name)`, `assert_at(frame, kind, args)`, `assert_end(kind, args=[])`, `total_frames()`, `frame_for(peer_id, frame) -> PlayerInputScript.InputFrame`, `captures() -> Array[Dictionary]`, `assertions() -> Array[Dictionary]`.
- Consumes: `res://player/player_input.gd` (`PlayerInputScript.InputFrame` with `axis: float`, `jump: bool`, `action: bool`).

`InputTimeline` is pure logic and runs headless, so it gets a fast unit test in the existing suite. The constructor takes a `total_frames` hint; `total_frames()` returns the max of the hint and the last capture/assert frame seen. `frame_for(peer_id, frame)` merges all matching `add` ranges for that peer: `axis` from the latest matching range wins; `jump`/`action` are OR-combined across all matching ranges so a jump burst inside a walk range works.

- [ ] **Step 1: Write the failing test**

`game/tests/unit/test_input_timeline.gd`:
```gdscript
extends SceneTree

const InputTimelineScript := preload("res://tests/platform/input_timeline.gd")

func _init() -> void:
	var failures := 0
	var t := InputTimelineScript.new(300)
	if t.total_frames() != 300:
		push_error("total_frames should honor hint"); failures += 1
	t.add(1, 0, 180, {"axis": 1.0})
	var f := t.frame_for(1, 50)
	if f.axis != 1.0 or f.jump or f.action:
		push_error("frame_for single range failed"); failures += 1
	var f0 := t.frame_for(1, 200)
	if f0.axis != 0.0:
		push_error("frame_for outside range should be neutral"); failures += 1
	t.add(1, 30, 35, {"axis": 1.1, "jump": true})
	var fj := t.frame_for(1, 32)
	if fj.axis != 1.1 or not fj.jump:
		push_error("overlapping ranges should merge (latest axis + OR jump)"); failures += 1
	t.add(2, 0, 200, {"axis": 1.0})
	if t.frame_for(2, 100).axis != 1.0:
		push_error("peer 2 independent input failed"); failures += 1
	if t.frame_for(1, 100).jump:
		push_error("peer 1 jump should not persist outside burst"); failures += 1
	t.capture(60, "meadow_start")
	t.capture(150, "meadow_mid")
	var caps := t.captures()
	if caps.size() != 2 or caps[0].frame != 60 or caps[0].name != "meadow_start":
		push_error("captures not recorded correctly"); failures += 1
	t.assert_at(250, "position_gt", [1, "x", 400])
	t.assert_end("no_errors")
	var asserts := t.assertions()
	if asserts.size() != 2:
		push_error("assertions not recorded"); failures += 1
	if asserts[0].kind != "position_gt" or asserts[0].frame != 250:
		push_error("assert_at not recorded correctly"); failures += 1
	if asserts[1].kind != "no_errors" or asserts[1].has("frame"):
		push_error("assert_end should have no frame key"); failures += 1
	var t2 := InputTimelineScript.new(10)
	t2.capture(50, "late")
	if t2.total_frames() != 50:
		push_error("total_frames should grow to last capture"); failures += 1
	if failures == 0:
		print("VISUAL_TEST_RESULT name=input_timeline_unit status=pass")
		quit(0)
	else:
		print("VISUAL_TEST_RESULT name=input_timeline_unit status=fail")
		quit(1)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless --path game -s res://tests/unit/test_input_timeline.gd`
Expected: FAIL — preload of `InputTimeline` fails.

- [ ] **Step 3: Implement InputTimeline**

`game/tests/platform/input_timeline.gd`:
```gdscript
class_name InputTimeline
extends RefCounted

const PlayerInputScript := preload("res://player/player_input.gd")

var _hint_frames: int = 0
var _entries: Array[Dictionary] = []
var _captures: Array[Dictionary] = []
var _assertions: Array[Dictionary] = []

func _init(total_frames_hint: int = 0) -> void:
	_hint_frames = maxi(total_frames_hint, 0)

func add(peer_id: int, start_frame: int, end_frame: int, input: Dictionary) -> void:
	_entries.append({"peer_id": peer_id, "start": start_frame, "end": end_frame, "input": input})

func capture(frame: int, name: String) -> void:
	_captures.append({"frame": frame, "name": name})

func assert_at(frame: int, kind: String, args: Array) -> void:
	_assertions.append({"frame": frame, "kind": kind, "args": args})

func assert_end(kind: String, args: Array = []) -> void:
	_assertions.append({"kind": kind, "args": args})

func total_frames() -> int:
	var max_frame := _hint_frames
	for c in _captures:
		max_frame = maxi(max_frame, int(c.frame))
	for a in _assertions:
		if a.has("frame"):
			max_frame = maxi(max_frame, int(a.frame))
	return max_frame

func frame_for(peer_id: int, frame: int) -> PlayerInputScript.InputFrame:
	var out := PlayerInputScript.InputFrame.new()
	var latest_axis: float = 0.0
	var have_axis := false
	for e in _entries:
		if int(e.peer_id) != peer_id:
			continue
		if frame < int(e.start) or frame > int(e.end):
			continue
		var input: Dictionary = e.input
		if input.has("axis"):
			latest_axis = float(input.axis)
			have_axis = true
		if input.has("jump") and bool(input.jump):
			out.jump = true
		if input.has("action") and bool(input.action):
			out.action = true
	out.axis = latest_axis if have_axis else 0.0
	return out

func captures() -> Array[Dictionary]:
	return _captures

func assertions() -> Array[Dictionary]:
	return _assertions
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless --path game -s res://tests/unit/test_input_timeline.gd`
Expected: PASS, prints `VISUAL_TEST_RESULT name=input_timeline_unit status=pass`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add game/tests/platform/input_timeline.gd game/tests/unit/test_input_timeline.gd
git commit -m "feat(visual-tests): add InputTimeline with headless unit test"
```

---

### Task 2: TestRunner core harness

**Files:**
- Create: `game/tests/platform/test_runner.gd`

**Interfaces:**
- Consumes: `InputTimeline` (Task 1), `res://player/player_input.gd`, the level scene path mapping.
- Produces: a Godot process that prints `VISUAL_TEST_RESULT name=<test> status=<pass|fail>` and writes `test-output/<test>/result.json` plus `<name>.png` screenshots. Subclasses override `_build_timeline() -> InputTimeline` and optionally `_level_scene_path() -> String`.

The `TestRunner` reads `--test` and `--level` from `OS.get_cmdline_user_args()`. Level name → scene path mapping: `sunny_forest` → `res://levels/sunny_forest.tscn` (snake-cased level id maps to `res://levels/<id>.tscn`; unknown levels fail with `SCENE_LOAD_FAILURE`). The output directory is `test-output/<test_name>/` resolved under `res://` (i.e. the project directory), created with `DirAccess.make_dir_recursive_absolute`.

Per-frame bug detection: out-of-world (`global_position.y > 2000`), softlock (neither hero moved > 5px in last 180 frames), HUD presence at capture frames (`HUD/GameplayHud` exists and `visible`). These are recorded in `result.json` under `alerts` and fail the test.

`result.json` schema:
```json
{
  "test": "sunny_forest_walk",
  "level": "sunny_forest",
  "status": "pass|fail",
  "failure_reason": "OUT_OF_WORLD|SOFTLOCK|RENDER_FAILURE|SCENE_LOAD_FAILURE|ASSERTION|none",
  "assertions": [{"kind": "position_gt", "args": [...], "frame": 250, "passed": true, "message": "...", "needs_log_scan": false}],
  "captures": [{"name": "meadow_start", "frame": 60, "path": "meadow_start.png", "render_ok": true}],
  "alerts": ["out_of_world@frame 120"],
  "state_snapshots": [{"frame": 60, "rabbit": [x,y], "fox": [x,y], "score": 0, "rabbit_hearts": 3, "fox_hearts": 4, "finished": false}],
  "error_log": []
}
```

- [ ] **Step 1: Implement TestRunner**

`game/tests/platform/test_runner.gd`:
```gdscript
class_name TestRunner
extends SceneTree

const InputTimelineScript := preload("res://tests/platform/input_timeline.gd")
const PlayerInputScript := preload("res://player/player_input.gd")

const VIEWPORT_W := 1340
const VIEWPORT_H := 800
const PHYSICS_HZ := 30
const SOFTLOCK_WINDOW := 180
const OUT_OF_WORLD_Y := 2000.0

var _test_name: String = "visual_test"
var _level_id: String = "sunny_forest"
var _timeline: InputTimelineScript = null
var _viewport: SubViewport = null
var _level: Node2D = null
var _rabbit: CharacterBody2D = null
var _fox: CharacterBody2D = null
var _out_dir: String = ""
var _result: Dictionary = {}
var _rabbit_history: Array[Vector2] = []
var _fox_history: Array[Vector2] = []


func _init() -> void:
	_read_args()
	call_deferred("_run")


func _read_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--test="):
			_test_name = arg.substr(7)
		elif arg.begins_with("--level="):
			_level_id = arg.substr(8)


# Subclasses override this to build the timeline.
func _build_timeline() -> InputTimelineScript:
	return InputTimelineScript.new(0)


func _level_scene_path() -> String:
	return "res://levels/%s.tscn" % _level_id


func _run() -> void:
	_init_result()
	_out_dir = "test-output/%s" % _test_name
	DirAccess.make_dir_recursive_absolute("res://%s" % _out_dir)
	_timeline = _build_timeline()
	_setup_viewport()
	if _level == null:
		_finish("fail", "SCENE_LOAD_FAILURE")
		return
	await get_tree().process_frame  # let _ready fire
	_disable_auto_processing()
	_run_loop()
	await get_tree().process_frame
	_evaluate_end_assertions()
	_finish(_result.status, _result.failure_reason)


func _init_result() -> void:
	_result = {
		"test": _test_name,
		"level": _level_id,
		"status": "pass",
		"failure_reason": "none",
		"assertions": [],
		"captures": [],
		"alerts": [],
		"state_snapshots": [],
		"error_log": [],
	}


func _setup_viewport() -> void:
	var scene := load(_level_scene_path())
	if scene == null or not scene is PackedScene:
		push_error("cannot load level scene: %s" % _level_scene_path())
		return
	_level = scene.instantiate()
	if _level == null:
		push_error("cannot instantiate level scene")
		return
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(VIEWPORT_W, VIEWPORT_H)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.disable_3d = true
	_viewport.add_child(_level)
	get_root().add_child(_viewport)
	_rabbit = _level.get_node_or_null("Rabbit")
	_fox = _level.get_node_or_null("Fox")


func _disable_auto_processing() -> void:
	if _level != null:
		_level.set_physics_process(false)
		_level.set_process(false)
	if _rabbit != null:
		_rabbit.set_physics_process(false)
	if _fox != null:
		_fox.set_physics_process(false)


func _run_loop() -> void:
	var delta := 1.0 / float(PHYSICS_HZ)
	var total := _timeline.total_frames()
	for frame in range(total + 1):
		var in1 := _timeline.frame_for(1, frame)
		var in2 := _timeline.frame_for(2, frame)
		_rabbit.apply_input(in1)
		_fox.apply_input(in2)
		_rabbit.physics_step(delta)
		_fox.physics_step(delta)
		_level._step_level(delta)
		_record_history()
		_run_bug_detection(frame)
		_run_frame_assertions(frame)
		_maybe_capture(frame)
		_record_state_snapshot(frame)
		if _result.status == "fail" and _result.failure_reason != "none":
			break
		await get_tree().process_frame


func _record_history() -> void:
	_rabbit_history.append(_rabbit.global_position)
	_fox_history.append(_fox.global_position)


func _run_bug_detection(frame: int) -> void:
	if _rabbit.global_position.y > OUT_OF_WORLD_Y or _fox.global_position.y > OUT_OF_WORLD_Y:
		_add_alert("out_of_world@frame %d" % frame)
		_fail("OUT_OF_WORLD")
	if frame >= SOFTLOCK_WINDOW:
		var r0 := _rabbit_history[frame - SOFTLOCK_WINDOW]
		var f0 := _fox_history[frame - SOFTLOCK_WINDOW]
		var r_moved := _rabbit.global_position.distance_to(r0) > 5.0
		var f_moved := _fox.global_position.distance_to(f0) > 5.0
		if not r_moved and not f_moved:
			_add_alert("softlock@frame %d" % frame)
			_fail("SOFTLOCK")


func _run_frame_assertions(frame: int) -> void:
	for a in _timeline.assertions():
		if not a.has("frame") or int(a.frame) != frame:
			continue
		_evaluate_assertion(a)


func _maybe_capture(frame: int) -> void:
	for c in _timeline.captures():
		if int(c.frame) != frame:
			continue
		var img := _viewport.get_texture().get_image()
		var render_ok := img != null
		var path := "%s/%s.png" % [_out_dir, c.name]
		if render_ok:
			var err := img.save_png("res://%s" % path)
			render_ok = err == OK
		else:
			_fail("RENDER_FAILURE")
		_result.captures.append({
			"name": c.name, "frame": frame, "path": "%s.png" % c.name, "render_ok": render_ok
		})
		# HUD presence check at capture frames
		var hud := _level.get_node_or_null("HUD/GameplayHud")
		if hud == null or not hud.visible:
			_add_alert("hud_missing@frame %d" % frame)


func _record_state_snapshot(frame: int) -> void:
	# Snapshot at capture frames and the final frame to keep result.json small.
	var is_capture := false
	for c in _timeline.captures():
		if int(c.frame) == frame:
			is_capture = true
			break
	if not is_capture and frame != _timeline.total_frames():
		return
	var score := 0
	if _level.has_method("get") and _level.get("team_score") != null:
		score = int(_level.get("team_score").total)
	_result.state_snapshots.append({
		"frame": frame,
		"rabbit": [_rabbit.global_position.x, _rabbit.global_position.y],
		"fox": [_fox.global_position.x, _fox.global_position.y],
		"score": score,
		"rabbit_hearts": int(_rabbit.hearts),
		"fox_hearts": int(_fox.hearts),
		"finished": _level.is_finished(),
	})


func _evaluate_end_assertions() -> void:
	for a in _timeline.assertions():
		if a.has("frame"):
			continue
		_evaluate_assertion(a)


func _evaluate_assertion(a: Dictionary) -> void:
	var kind: String = a.kind
	var args: Array = a.args
	var passed := true
	var message := ""
	var needs_log_scan := false
	var final_frame := _timeline.total_frames()
	match kind:
		"position_gt":
			var peer_id := int(args[0])
			var axis := String(args[1])
			var value := float(args[2])
			var hero := _hero_for(peer_id)
			var v := hero.global_position.x if axis == "x" else hero.global_position.y
			passed = v > value
			message = "peer %d %s=%.1f > %.1f" % [peer_id, axis, v, value]
		"position_lt":
			var peer_id := int(args[0])
			var axis := String(args[1])
			var value := float(args[2])
			var hero := _hero_for(peer_id)
			var v := hero.global_position.x if axis == "x" else hero.global_position.y
			passed = v < value
			message = "peer %d %s=%.1f < %.1f" % [peer_id, axis, v, value]
		"position_eq":
			var hero := _hero_for(int(args[0]))
			var x := float(args[1]); var y := float(args[2]); var tol := float(args[3])
			passed = hero.global_position.distance_to(Vector2(x, y)) <= tol
			message = "peer %d at %s vs (%.1f,%.1f) tol %.1f" % [int(args[0]), str(hero.global_position), x, y, tol]
		"score_eq":
			var ts := _level.get("team_score")
			passed = int(ts.total) == int(args[0])
			message = "score=%d == %d" % [int(ts.total), int(args[0])]
		"score_gt":
			var ts := _level.get("team_score")
			passed = int(ts.total) > int(args[0])
			message = "score=%d > %d" % [int(ts.total), int(args[0])]
		"gate_open":
			passed = _level.gate_is_open(String(args[0]))
			message = "gate %s open" % String(args[0])
		"gate_closed":
			passed = not _level.gate_is_open(String(args[0]))
			message = "gate %s closed" % String(args[0])
		"hearts_eq":
			var hero := _hero_for(int(args[0]))
			passed = int(hero.hearts) == int(args[1])
			message = "peer %d hearts=%d == %d" % [int(args[0]), int(hero.hearts), int(args[1])]
		"hearts_gt":
			var hero := _hero_for(int(args[0]))
			passed = int(hero.hearts) > int(args[1])
			message = "peer %d hearts=%d > %d" % [int(args[0]), int(hero.hearts), int(args[1])]
		"no_errors":
			passed = true
			needs_log_scan = true
			message = "no_errors (resolved by orchestrator log scan)"
		"both_alive":
			passed = int(_rabbit.hearts) > 0 and int(_fox.hearts) > 0
			message = "hearts rabbit=%d fox=%d" % [_rabbit.hearts, _fox.hearts]
		"finished":
			passed = _level.is_finished()
			message = "finished=%s" % str(_level.is_finished())
		"not_finished":
			passed = not _level.is_finished()
			message = "finished=%s" % str(_level.is_finished())
		"bubble_count_eq":
			passed = _level.active_bubble_count() == int(args[0])
			message = "bubbles=%d == %d" % [_level.active_bubble_count(), int(args[0])]
		"ammo_eq":
			var peer_id := int(args[0])
			var ammo := _level.get("bubble_ammo")
			passed = int(ammo.remaining(peer_id)) == int(args[1])
			message = "peer %d ammo=%d == %d" % [peer_id, int(ammo.remaining(peer_id)), int(args[1])]
		_:
			passed = false
			message = "unknown assertion kind: %s" % kind
	var entry := {"kind": kind, "args": args, "passed": passed, "message": message, "needs_log_scan": needs_log_scan}
	if a.has("frame"):
		entry["frame"] = int(a.frame)
	_result.assertions.append(entry)
	if not passed and not needs_log_scan:
		_fail("ASSERTION")


func _hero_for(peer_id: int) -> CharacterBody2D:
	return _rabbit if peer_id == 1 else _fox


func _add_alert(msg: String) -> void:
	_result.alerts.append(msg)


func _fail(reason: String) -> void:
	_result.status = "fail"
	_result.failure_reason = reason


func _finish(status: String, reason: String) -> void:
	_result.status = status
	_result.failure_reason = reason
	var f := FileAccess.open("res://%s/result.json" % _out_dir, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_result, "\t"))
		f.close()
	print("VISUAL_TEST_RESULT name=%s status=%s" % [_test_name, _result.status])
	quit(1 if _result.status == "fail" else 0)
```

- [ ] **Step 2: Verify it loads (smoke)**

Run: `godot --headless --path game -s res://tests/platform/test_runner.gd -- --test=smoke --level=sunny_forest`
Expected: prints `VISUAL_TEST_RESULT name=smoke status=pass` (empty timeline → 0 frames → no assertions fail), writes `test-output/smoke/result.json`. (Headless cannot capture screenshots, but with no capture points this smoke run should still pass. If the SubViewport returns null in headless and there are no captures, that's fine.)

- [ ] **Step 3: Commit**

```bash
git add game/tests/platform/test_runner.gd
git commit -m "feat(visual-tests): add TestRunner harness with manual simulation loop"
```

---

### Task 3: compare_screenshots.py + self-test

**Files:**
- Create: `scripts/compare_screenshots.py`

**Interfaces:**
- Produces: `compare(baseline: str, current: str, threshold: float = 0.02) -> dict` returning `{"changed_pixel_ratio": float, "max_delta": int, "diff_image_path": str|None, "regression": bool}`. Also a `__main__` self-test invoked with `--self-test`.

PNG decoder handles 8-bit, color type 6 (RGBA) and color type 2 (RGB), all five filters. Diff image is an RGBA PNG with changed pixels in red (255,0,0,255) and unchanged in white (255,255,255,255), same dimensions, written next to the current image as `<current>.diff.png`.

- [ ] **Step 1: Write the self-test first (in the same file, run before implementing decode)**

The self-test creates two PNGs by encoding them with the same encoder (so we test decode+compare end to end):
- `a.png`: solid red 4×2.
- `b.png`: same as a except one pixel changed to green.
- `compare(a, a)` → 0% changed, `regression == False`.
- `compare(a, b)` → >0% changed, `regression == True` with threshold 0.0.

- [ ] **Step 2: Run self-test to verify it fails**

Run: `python3 scripts/compare_screenshots.py --self-test`
Expected: FAIL — module functions not implemented / import error.

- [ ] **Step 3: Implement compare_screenshots.py**

`scripts/compare_screenshots.py` (stdlib only: `struct`, `zlib`, `pathlib`, `sys`):
```python
#!/usr/bin/env python3
"""Stdlib-only PNG comparison: decode RGBA/RGB PNGs, pixel diff, write diff PNG."""
import struct
import zlib
from pathlib import Path
import sys

_PNG_SIG = b"\x89PNG\r\n\x1a\n"


def _read_chunks(data: bytes):
    if not data.startswith(_PNG_SIG):
        raise ValueError("not a PNG")
    offset = len(_PNG_SIG)
    chunks = []
    while offset < len(data):
        length = struct.unpack(">I", data[offset:offset + 4])[0]
        ctype = data[offset + 4:offset + 8].decode("ascii", "replace")
        cdata = data[offset + 8:offset + 8 + length]
        chunks.append((ctype, cdata))
        offset += 8 + length + 4
    return chunks


def _paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


def decode_png(path: str):
    """Return (width, height, rgba_bytes) for an 8-bit RGB/RGBA PNG."""
    data = Path(path).read_bytes()
    chunks = _read_chunks(data)
    width = height = bit_depth = color_type = 0
    idat = bytearray()
    for ctype, cdata in chunks:
        if ctype == "IHDR":
            width, height, bit_depth, color_type = struct.unpack(">IIBB", cdata[:10])
        elif ctype == "IDAT":
            idat += cdata
    if bit_depth != 8:
        raise ValueError("only 8-bit PNG supported")
    channels = {2: 3, 6: 4}.get(color_type)
    if channels is None:
        raise ValueError("only color type 2 (RGB) or 6 (RGBA) supported")
    raw = zlib.decompress(bytes(idat))
    stride = width * channels
    out = bytearray(width * height * 4)
    prev_row = bytearray(stride)
    pos = 0
    for y in range(height):
        ftype = raw[pos]; pos += 1
        row = bytearray(raw[pos:pos + stride]); pos += stride
        for x in range(stride):
            a = row[x - channels] if x >= channels else 0
            b = prev_row[x]
            c = prev_row[x - channels] if x >= channels else 0
            if ftype == 1:
                row[x] = (row[x] + a) & 0xFF
            elif ftype == 2:
                row[x] = (row[x] + b) & 0xFF
            elif ftype == 3:
                row[x] = (row[x] + ((a + b) >> 1)) & 0xFF
            elif ftype == 4:
                row[x] = (row[x] + _paeth(a, b, c)) & 0xFF
        for x in range(width):
            r = row[x * channels]
            g = row[x * channels + 1]
            bl = row[x * channels + 2]
            al = row[x * channels + 3] if channels == 4 else 255
            o = (y * width + x) * 4
            out[o] = r; out[o + 1] = g; out[o + 2] = bl; out[o + 3] = al
        prev_row = row
    return width, height, bytes(out)


def encode_png(width: int, height: int, rgba: bytes) -> bytes:
    """Encode an RGBA byte buffer as a filter-type-0 PNG (for self-test + diff)."""
    def chunk(ctype: bytes, body: bytes) -> bytes:
        return (struct.pack(">I", len(body)) + ctype + body
                + struct.pack(">I", zlib.crc32(ctype + body) & 0xFFFFFFFF))
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)
        raw += rgba[y * stride:(y + 1) * stride]
    idat = zlib.compress(bytes(raw), 9)
    return _PNG_SIG + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b"")


def compare(baseline: str, current: str, threshold: float = 0.02) -> dict:
    w1, h1, a = decode_png(baseline)
    w2, h2, b = decode_png(current)
    if (w1, h1) != (w2, h2):
        return {"changed_pixel_ratio": 1.0, "max_delta": 255,
                "diff_image_path": None, "regression": True,
                "message": "size mismatch %dx%d vs %dx%d" % (w1, h1, w2, h2)}
    total = w1 * h1
    changed = 0
    max_delta = 0
    diff = bytearray(total * 4)
    for i in range(total):
        o = i * 4
        d = max(abs(a[o] - b[o]), abs(a[o + 1] - b[o + 1]), abs(a[o + 2] - b[o + 2]))
        if d > max_delta:
            max_delta = d
        if d > 0:
            changed += 1
            diff[o] = 255; diff[o + 1] = 0; diff[o + 2] = 0; diff[o + 3] = 255
        else:
            diff[o] = 255; diff[o + 1] = 255; diff[o + 2] = 255; diff[o + 3] = 255
    ratio = changed / total if total else 0.0
    diff_path = None
    if changed > 0:
        diff_path = str(Path(current).with_suffix(".diff.png"))
        Path(diff_path).write_bytes(encode_png(w1, h1, bytes(diff)))
    return {"changed_pixel_ratio": ratio, "max_delta": max_delta,
            "diff_image_path": diff_path, "regression": ratio > threshold}


def _self_test() -> int:
    tmp = Path("test-output/_compare_selftest")
    tmp.mkdir(parents=True, exist_ok=True)
    red = bytes([255, 0, 0, 255] * 8)
    green_one = bytearray(red)
    green_one[4:8] = bytes([0, 255, 0, 255])
    a = tmp / "a.png"; b = tmp / "b.png"
    a.write_bytes(encode_png(4, 2, red))
    b.write_bytes(encode_png(4, 2, bytes(green_one)))
    r1 = compare(str(a), str(a), 0.0)
    r2 = compare(str(a), str(b), 0.0)
    ok = True
    if r1["changed_pixel_ratio"] != 0.0 or r1["regression"]:
        print("FAIL: identical images should be 0% diff"); ok = False
    if r2["changed_pixel_ratio"] <= 0.0 or not r2["regression"]:
        print("FAIL: modified image should be non-zero diff and a regression"); ok = False
    if r2["diff_image_path"] is None or not Path(r2["diff_image_path"]).exists():
        print("FAIL: diff image not written"); ok = False
    print("PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        sys.exit(_self_test())
    print("usage: compare_screenshots.py --self-test  (import compare() for library use)")
    sys.exit(0)
```

- [ ] **Step 4: Run self-test to verify it passes**

Run: `python3 scripts/compare_screenshots.py --self-test`
Expected: `PASS`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/compare_screenshots.py
git commit -m "feat(visual-tests): add stdlib PNG compare with self-test"
```

---

### Task 4: Example test — sunny_forest_walk

**Files:**
- Create: `game/tests/platform/test_sunny_forest_walk.gd`

**Interfaces:**
- Consumes: `TestRunner` (Task 2), `InputTimeline` (Task 1).

This is the first end-to-end visual test and validates the whole GDScript harness. Rabbit walks right and jumps twice; fox follows. Three captures; asserts both heroes advanced and no errors / both alive.

- [ ] **Step 1: Write the test**

`game/tests/platform/test_sunny_forest_walk.gd`:
```gdscript
extends "res://tests/platform/test_runner.gd"


func _build_timeline() -> InputTimeline:
	var t := InputTimeline.new(300)
	t.add(1, 0, 180, {"axis": 1.0})
	t.add(1, 30, 35, {"axis": 1.0, "jump": true})
	t.add(1, 60, 65, {"axis": 1.0, "jump": true})
	t.add(2, 0, 200, {"axis": 1.0})
	t.add(2, 45, 50, {"axis": 1.0, "jump": true})
	t.capture(60, "meadow_start")
	t.capture(150, "meadow_mid")
	t.capture(250, "meadow_end")
	t.assert_at(250, "position_gt", [1, "x", 400])
	t.assert_at(250, "position_gt", [2, "x", 300])
	t.assert_end("no_errors")
	t.assert_end("both_alive")
	return t
```

- [ ] **Step 2: Run it with a display**

Run: `DISPLAY=:0 godot --path game -s res://tests/platform/test_sunny_forest_walk.gd -- --test=sunny_forest_walk --level=sunny_forest`
Expected: prints `VISUAL_TEST_RESULT name=sunny_forest_walk status=pass`, writes `test-output/sunny_forest_walk/result.json` and three PNGs (`meadow_start.png`, `meadow_mid.png`, `meadow_end.png`).

- [ ] **Step 3: Inspect the output**

Verify: `test-output/sunny_forest_walk/result.json` has `"status": "pass"`, three captures with `render_ok: true`, and the two `position_gt` assertions `passed: true`. Open one PNG to confirm it is a real screenshot of the meadow (not blank).

- [ ] **Step 4: Commit**

```bash
git add game/tests/platform/test_sunny_forest_walk.gd
git commit -m "feat(visual-tests): add sunny_forest_walk example test"
```

---

### Task 5: run_visual_tests.py orchestrator + HTML report

**Files:**
- Create: `scripts/run_visual_tests.py`

**Interfaces:**
- Consumes: `compare_screenshots.compare` (Task 3), Godot binary on PATH (or `GODOT_BIN`), `game/tests/platform/test_*.gd`.
- Produces: `test-output/<test>/result.json` (post-processed with `error_log` and resolved `no_errors`), `test-output/baselines/<test>/<name>.png` (on `--update-baselines`), and `test-output/report.html`.

Flow per spec: discover tests, launch each with `DISPLAY` set, capture combined stdout/stderr, scan for error lines, read `result.json`, compare screenshots against baselines (or save as new baselines on first run / `--update-baselines`), generate HTML report with per-test badges, side-by-side baseline|current|diff, state snapshots, error excerpts, and alerts.

- [ ] **Step 1: Implement the orchestrator**

`scripts/run_visual_tests.py` (stdlib only: `subprocess`, `json`, `pathlib`, `html`, `argparse`, `os`, `re`, `sys`). Import `compare` from `compare_screenshots` via `sys.path` insertion of the scripts dir.

Key behaviors:
- `--test <name>` runs one test; `--update-baselines` copies current screenshots into `test-output/baselines/<test>/` (creating/overwriting); default threshold 0.02.
- Error scan regex: lines containing `SCRIPT ERROR`, `ERROR`, `push_error` (case-sensitive on those tokens) are collected into `error_log`; if non-empty, every assertion with `needs_log_scan` is marked `passed: false` and `result.status` becomes `fail` with `failure_reason = "ERROR_LOG"` (unless already a harder failure).
- If `DISPLAY` unset → print clear message, exit 0 (so `test_all.sh` gating can call it unconditionally and it self-skips). Actually the spec says the orchestrator prints a clear message and exits; `test_all.sh` gates on `DISPLAY` anyway. Implement: if `DISPLAY` unset, print "DISPLAY not set; skipping visual tests." and exit 0.
- Non-zero Godot exit with no `result.json` → record `status: fail`, `failure_reason: "CRASH"`.
- HTML report: per-test card with badge, capture thumbnails (baseline/current/diff) embedded via relative file paths, state snapshot table, error log `<pre>`, alerts list.

- [ ] **Step 2: Run all visual tests through the orchestrator**

Run: `DISPLAY=:0 python3 scripts/run_visual_tests.py`
Expected: runs `sunny_forest_walk` (and any other platform tests present), writes `test-output/report.html`, prints a summary. On first run, baselines are created.

- [ ] **Step 3: Verify the report**

Open `test-output/report.html` in a browser (or `grep` for the test name + `pass` badge). Confirm: one card for `sunny_forest_walk`, pass badge, three capture rows, state snapshot entries.

- [ ] **Step 4: Commit**

```bash
git add scripts/run_visual_tests.py
git commit -m "feat(visual-tests): add Python orchestrator and HTML report"
```

---

### Task 6: live_inspect.gd

**Files:**
- Create: `game/tests/platform/live_inspect.gd`

Interactive mode: loads the level into the root window (not a SubViewport), keyboard drives the local hero (A/D or arrows for axis, W/Space for jump, E for action), optional `--script-fox` auto-walks the fox, `F12` captures a screenshot to `test-output/live/<timestamp>.png`, `F11` prints full game state, `ESC` quits. Reads `--level` from user args.

- [ ] **Step 1: Implement live_inspect.gd**

`game/tests/platform/live_inspect.gd` (extends `SceneTree`, adds the level to `get_root()`, uses `Input` polling in a `_process`-like loop via `process_frame` signal). Keyboard → `InputFrame` → `rabbit.apply_input` (local hero). Does NOT disable the level's auto-processing (the operator wants the real game loop, including touch-controls routing — but touch is inactive on desktop, so keyboard input via `apply_input` each frame works because `route_control_frames` overwrites with empty touch; **therefore** set the level's `set_physics_process(false)` and manually step, same as TestRunner, but read keyboard for the local hero and a simple auto-walk for the fox). This keeps input routing under our control while still rendering to the root window.

- [ ] **Step 2: Smoke-run live inspect**

Run: `DISPLAY=:0 godot --path game -s res://tests/platform/live_inspect.gd -- --level=sunny_forest`
Expected: a Godot window opens showing the meadow; pressing A/D moves the rabbit; F12 writes a screenshot under `test-output/live/`; ESC quits. (Operator-driven verification — the agent confirms the window opens and a screenshot is written on F12 via a scripted key injection if needed, or leaves operator confirmation to the human.)

- [ ] **Step 3: Commit**

```bash
git add game/tests/platform/live_inspect.gd
git commit -m "feat(visual-tests): add live inspection mode"
```

---

### Task 7: Additional example tests (gates, full)

**Files:**
- Create: `game/tests/platform/test_sunny_forest_gates.gd`
- Create: `game/tests/platform/test_sunny_forest_full.gd`

`test_sunny_forest_gates`: walks both heroes to the fallen-log crossing, rabbit pushes the log (action near `fallen-log`), fox hits the `overhead-switch`, asserts `gate_open` `fallen-log` and `not_finished`.

`test_sunny_forest_full`: collects stars, opens the bubble-grove gate (both flowers), picks up the bubble power-up, fires a bubble, asserts `score_gt 0`, `ammo_eq [1, >=0]`, and `finished` after both heroes reach the magical tree.

These require knowing interactable world positions; the implementer should read `game/levels/sunny_forest.tscn` node positions to script the heroes to the right x-coordinates and trigger actions at the right frames. Keep timelines under ~600 frames.

- [ ] **Step 1: Write test_sunny_forest_gates.gd** (read the scene for FallenLog/OverheadSwitch x positions)
- [ ] **Step 2: Run it** — `DISPLAY=:0 python3 scripts/run_visual_tests.py --test sunny_forest_gates` — verify pass.
- [ ] **Step 3: Write test_sunny_forest_full.gd**
- [ ] **Step 4: Run it** — `DISPLAY=:0 python3 scripts/run_visual_tests.py --test sunny_forest_full` — verify pass.
- [ ] **Step 5: Commit**

```bash
git add game/tests/platform/test_sunny_forest_gates.gd game/tests/platform/test_sunny_forest_full.gd
git commit -m "feat(visual-tests): add gates and full sunny forest example tests"
```

---

### Task 8: Integration (test_all.sh, .gitignore, docs)

**Files:**
- Modify: `scripts/test_all.sh`
- Modify: `.gitignore`
- Create: `docs/visual-testing.md`

- [ ] **Step 1: Exclude platform tests from the headless find and add a DISPLAY-gated visual section**

In `scripts/test_all.sh`, change the `find` to exclude the platform dir:
```bash
done < <(find game/tests -name 'test_*.gd' -type f ! -name 'test_session_pair.gd' ! -name 'test_reconnect_pair.gd' ! -path 'game/tests/platform/*' | sort)
```
Append at the end:
```bash
if [ -n "${DISPLAY:-}" ]; then
  python3 scripts/run_visual_tests.py
else
  echo "DISPLAY not set; skipping visual tests."
fi
```

- [ ] **Step 2: Update .gitignore**

Append:
```
test-output/
!test-output/baselines/
```

- [ ] **Step 3: Write docs/visual-testing.md**

Operator-facing doc: what the platform is, the four commands from the spec's Commands section, how baselines work (`--update-baselines`), how to read the HTML report, the live inspect hotkeys, and the constraint that visual tests need `DISPLAY=:0`.

- [ ] **Step 4: Run the full gate**

Run: `bash scripts/test_all.sh`
Expected: all existing headless tests pass (including the new `test_input_timeline.gd`), LAN pair tests pass, and the visual tests section runs (since `DISPLAY=:0` is set) and passes. Paste real output.

- [ ] **Step 5: Commit**

```bash
git add scripts/test_all.sh .gitignore docs/visual-testing.md
git commit -m "feat(visual-tests): integrate with test_all.sh, gitignore, and docs"
```

---

## Self-Review

**Spec coverage:**
- InputTimeline (§InputTimeline) → Task 1.
- TestRunner + bug detection (§TestRunner) → Task 2 (out-of-world, softlock, HUD check, error scan via orchestrator per resolved decision #3).
- LiveInspect (§LiveInspect) → Task 6.
- Python orchestrator + HTML report (§Python Orchestrator) → Task 5.
- Screenshot comparison (§Screenshot Comparison) → Task 3.
- Example test sunny_forest_walk (§Example Test) → Task 4.
- File structure (§File Structure) → all tasks.
- Integration: test_all.sh DISPLAY gate, .gitignore, no changes to game code (§Integration) → Task 8.
- Commands (§Commands) → Task 8 docs + each task's run steps.
- Error handling (crash, null screenshot, scene load failure, missing baselines, no DISPLAY) → Task 2 (SCENE_LOAD_FAILURE, RENDER_FAILURE), Task 5 (CRASH, missing baselines → save as new, no DISPLAY → skip).
- Testing the platform itself (§Testing the Platform) → Task 1 unit test, Task 3 self-test, Task 5 report verification.

**Placeholder scan:** No TBD/TODO; every code step has real code or a concrete instruction (Task 7's "read the scene for positions" is a concrete instruction, not a placeholder).

**Type consistency:** `InputTimeline` constructor takes `total_frames_hint`; `frame_for` returns `PlayerInputScript.InputFrame`; `compare` returns the dict shape consumed by Task 5; `result.json` schema is identical between Task 2 (writer) and Task 5 (reader/post-processor).

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-08-29-visual-testing-platform.md`. Two execution options:

1. **Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** — I execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?
