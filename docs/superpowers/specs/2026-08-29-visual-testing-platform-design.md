# Visual Testing Platform Design

**Date:** 2026-08-29
**Status:** Approved
**Spec for:** PC-based automated game testing with screenshot capture, visual regression, and bug detection

## Problem

The game requires manual playtesting on two physical tablets to catch bugs. This is slow, operator-dependent, and makes it impossible to catch regressions automatically. The existing headless test suite covers logic and scene structure but has zero visual verification — no screenshots, no pixel inspection, no visual regression detection.

## Goal

A PC-based testing platform that:
1. Runs the game with scripted input for both heroes (no human needed)
2. Captures screenshots at key moments for visual review
3. Compares screenshots against baselines for visual regression detection
4. Automatically detects common bugs (softlocks, out-of-world falls, error log spam, HUD failures)
5. Provides a live inspection mode for manual debugging
6. Generates an HTML report with screenshots, diffs, and pass/fail status

## Constraints

- No new third-party dependencies (Godot + Python stdlib only)
- No changes to existing game code, autoloads, or `project.godot`
- Visual tests are separate from the existing headless test suite (don't break `test_all.sh`)
- Must run on this PC with `DISPLAY=:0` (NVIDIA RTX 5080, Godot 4.7.2, gl_compatibility renderer)
- Headless mode (`--headless`) cannot capture screenshots — the dummy renderer returns null textures
- Screenshots are captured via `SubViewport.get_texture().get_image().save_png()`
- Input is scripted via synthetic `InputFrame` objects, bypassing `TouchControls`
- Both heroes are scripted independently by peer_id (1=rabbit, 2=fox)
- Frame-based timing at 30fps physics tick for determinism

## Architecture

Three layers:

### 1. GDScript Test Harness (`game/tests/platform/`)

Runs inside Godot with the real display (not `--headless`). Creates a `SubViewport` at 1340×800, loads a level scene into it, scripts both heroes' input via synthetic `InputFrame` objects each physics tick, captures screenshots at defined frames, runs assertions on game state, and writes a JSON results file plus screenshots to an output directory.

### 2. Python Orchestrator (`scripts/run_visual_tests.py`)

Stdlib-only, runs outside Godot. Discovers test scripts, launches each as a Godot process with `DISPLAY` set, collects JSON results and screenshots, compares screenshots against baselines (pixel diff), and generates an HTML report.

### 3. Live Inspection Mode (`game/tests/platform/live_inspect.gd`)

Interactive mode. Loads any level into a SubViewport rendered to the root window. Operator watches the game in the Godot window, controls one hero via keyboard, optionally scripts the other, captures screenshots on hotkey, and prints game state to stdout on demand.

## Components

### InputTimeline (`game/tests/platform/input_timeline.gd`)

Maps frame ranges to `InputFrame` values for each hero. Frame-based at 30fps for determinism.

```gdscript
class_name InputTimeline
extends RefCounted

func add(peer_id: int, start_frame: int, end_frame: int, input: Dictionary) -> void
func capture(frame: int, name: String) -> void
func assert_at(frame: int, kind: String, args: Array) -> void
func assert_end(kind: String, args: Array = []) -> void
func total_frames() -> int
func frame_for(peer_id: int, frame: int) -> PlayerInputScript.InputFrame
func captures() -> Array[Dictionary]
func assertions() -> Array[Dictionary]
```

- `add(peer_id, start, end, input)`: schedules input for a hero between two frames. `input` keys: `axis` (float -1..1), `jump` (bool), `action` (bool). Overlapping ranges merge.
- `capture(frame, name)`: marks a frame for screenshot capture. The screenshot is saved as `<name>.png`.
- `assert_at(frame, kind, args)`: checks a condition at a specific frame.
- `assert_end(kind, args)`: checks a condition at the end of the timeline.

Assertion kinds:
- `position_gt`: `[peer_id, axis("x"|"y"), value]` — hero position must exceed value
- `position_lt`: `[peer_id, axis, value]`
- `position_eq`: `[peer_id, x, y, tolerance]`
- `score_eq`: `[value]` — team_score.total must equal value
- `score_gt`: `[value]`
- `gate_open`: `[gate_id]` — gate must be complete
- `gate_closed`: `[gate_id]`
- `hearts_eq`: `[peer_id, value]`
- `hearts_gt`: `[peer_id, value]`
- `no_errors`: no `push_error` or `SCRIPT ERROR` in the log
- `both_alive`: neither hero at 0 hearts
- `finished`: level.is_finished() must be true
- `not_finished`: level.is_finished() must be false
- `bubble_count_eq`: `[count]` — active_bubble_count must equal count
- `ammo_eq`: `[peer_id, count]`

### TestRunner (`game/tests/platform/test_runner.gd`)

The harness that plays a timeline against a level scene.

```gdscript
class_name TestRunner
extends SceneTree

func _init() -> void  # reads --level and --test args, calls _run deferred
func _run() -> void   # sets up SubViewport, loads level, plays timeline, captures, asserts, writes result.json
```

Flow:
1. Create `SubViewport` at 1340×800, `UPDATE_ALWAYS`, `disable_3d = true`
2. Load the level scene, add to SubViewport
3. Wait for `_ready()` (await process_frame)
4. For each frame 0..total_frames:
   a. Build `InputFrame` for each hero from the timeline
   b. Call `hero.apply_input(frame)` for both heroes
   c. Call `level._step_level(delta)` (1/30)
   d. Run any `assert_at` checks for this frame
   e. Run per-frame bug detection (out-of-world, softlock, error scan)
   f. If this frame is a capture point, save screenshot
5. Run `assert_end` checks
6. Write `result.json` with pass/fail, assertion results, state snapshots, screenshot paths
7. Print `VISUAL_TEST_RESULT name=<test> status=<pass|fail>` to stdout
8. `quit(0)` on pass, `quit(1)` on fail

Bug detection (checked every frame):
- **Out-of-world:** any hero `global_position.y > 2000`
- **Softlock:** neither hero position changed by > 5px in last 180 frames (6 seconds at 30fps)
- **Error scan:** Godot log output captured via `OS.execute("godot", ...)` stderr, or a custom logger hook; any `push_error` / `SCRIPT ERROR` line triggers an error assertion
- **HUD check:** at capture frames, verify `HUD/GameplayHud` node exists and is visible

### LiveInspect (`game/tests/platform/live_inspect.gd`)

Interactive mode for manual debugging.

```bash
godot --path game -s res://tests/platform/live_inspect.gd -- --level=sunny_forest
```

- Loads the level into the root window (not a SubViewport — operator sees it directly)
- Keyboard controls the local hero (A/D/W/E or arrows)
- Optional `--script-fox` flag runs a simple auto-walk script for the partner
- `F12` captures a screenshot to `test-output/live/<timestamp>.png`
- `F11` prints full game state to stdout (positions, score, hearts, gates, enemies)
- `ESC` quits

### Python Orchestrator (`scripts/run_visual_tests.py`)

Stdlib-only. Discovers and runs visual tests, compares screenshots, generates HTML report.

```bash
python3 scripts/run_visual_tests.py                    # run all
python3 scripts/run_visual_tests.py --test <name>      # run one
python3 scripts/run_visual_tests.py --update-baselines # regenerate baselines
```

Flow:
1. Discover `game/tests/platform/test_*.gd` files
2. For each test, launch `godot --path game -s res://tests/platform/test_<name>.gd -- --level=<level>`
3. Wait for process exit, read `test-output/<test_name>/result.json`
4. If baselines exist, compare each screenshot:
   - Load both PNGs (using `zlib` + manual PNG parsing, no PIL)
   - Pixel-by-pixel comparison, count changed pixels and max delta
   - If changed pixels > threshold (default 2%), flag as VISUAL_REGRESSION
   - Generate diff image (changed pixels in red, unchanged in white)
5. Generate `test-output/report.html` with:
   - Per-test pass/fail badge
   - Side-by-side baseline | current | diff
   - Game state at each capture point
   - Error log excerpts
   - Softlock/out-of-world/error alerts

### Screenshot Comparison (`scripts/compare_screenshots.py`)

Stdlib-only PNG comparison. Parses PNG with `zlib` decompression, compares RGBA pixels, generates diff PNG.

```python
def compare(baseline: str, current: str, threshold: float = 0.02) -> ComparisonResult
```

Returns: `changed_pixel_ratio`, `max_delta`, `diff_image_path`.

### Example Test: Sunny Forest Walk (`game/tests/platform/test_sunny_forest_walk.gd`)

```gdscript
extends "res://tests/platform/test_runner.gd"

func _build_timeline() -> InputTimeline:
    var t := InputTimeline.new(300)
    # Rabbit walks right through the meadow
    t.add(1, 0, 180, {"axis": 1.0})
    t.add(1, 30, 35, {"axis": 1.0, "jump": true})
    t.add(1, 60, 65, {"axis": 1.0, "jump": true})
    # Fox follows
    t.add(2, 0, 200, {"axis": 1.0})
    t.add(2, 45, 50, {"axis": 1.0, "jump": true})
    # Capture points
    t.capture(60, "meadow_start")
    t.capture(150, "meadow_mid")
    t.capture(250, "meadow_end")
    # Assertions
    t.assert_at(250, "position_gt", [1, "x", 400])
    t.assert_at(250, "position_gt", [2, "x", 300])
    t.assert_end("no_errors")
    t.assert_end("both_alive")
    return t
```

## File Structure

```
game/tests/platform/
├── input_timeline.gd
├── test_runner.gd
├── live_inspect.gd
├── test_sunny_forest_walk.gd
├── test_sunny_forest_gates.gd
└── test_sunny_forest_full.gd

scripts/
├── run_visual_tests.py
└── compare_screenshots.py

test-output/                   # gitignored
├── baselines/                 # committed via --update-baselines
├── <test_name>/
│   ├── result.json
│   └── *.png
└── report.html

docs/
└── visual-testing.md
```

## Integration

- `scripts/test_all.sh`: adds a section that runs `python3 scripts/run_visual_tests.py` only if `DISPLAY` is set (skipped in headless CI)
- `.gitignore`: adds `test-output/` but not `test-output/baselines/`
- No changes to existing game code, autoloads, `project.godot`, or existing tests
- Visual tests are in `game/tests/platform/`, separate from `game/tests/unit/` and `game/tests/integration/`

## Commands

```bash
# Run all visual tests
python3 scripts/run_visual_tests.py

# Run one test
python3 scripts/run_visual_tests.py --test sunny_forest_walk

# Update baselines after intentional visual changes
python3 scripts/run_visual_tests.py --update-baselines

# Live inspection mode
godot --path game -s res://tests/platform/live_inspect.gd -- --level=sunny_forest
```

## Error Handling

- If Godot crashes during a test, the orchestrator detects non-zero exit and reports it
- If a screenshot is null (rendering failure), the test fails with RENDER_FAILURE
- If a level scene can't be loaded, the test fails with SCENE_LOAD_FAILURE
- If baselines don't exist for a test, screenshots are saved as new baselines (first run)
- If `DISPLAY` is not set, the orchestrator prints a clear message and exits (visual tests need a display)

## Testing the Platform Itself

- `test_runner.gd` is tested by the example test scripts — if they produce valid screenshots and correct pass/fail, the harness works
- `compare_screenshots.py` has a self-test: compare a PNG against itself (0% diff) and against a modified version (non-zero diff)
- `run_visual_tests.py` is tested by running it and checking the HTML report is generated with correct structure
