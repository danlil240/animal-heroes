# Visual Testing Platform

The visual testing platform runs the Animal Heroes game with scripted input on a
real display, captures screenshots at key moments, and compares them against
baselines to detect visual regressions. It complements the existing headless
test suite (which validates logic and scene structure) by adding pixel-level
verification.

## Requirements

- Godot 4.7.2 with a real display (`DISPLAY=:0`). Visual tests cannot run
  headless — Godot's dummy renderer produces null textures.
- Python 3.12+ (stdlib only, no pip packages).

## Commands

```bash
# Run all visual tests (requires DISPLAY)
python3 scripts/run_visual_tests.py

# Run a single test
python3 scripts/run_visual_tests.py --test sunny_forest_walk

# Update baselines after intentional visual changes
python3 scripts/run_visual_tests.py --update-baselines

# Live inspection mode (interactive, keyboard control)
godot --path game -s res://tests/platform/live_inspect.gd -- --level=sunny_forest

# With auto-walking fox partner
godot --path game -s res://tests/platform/live_inspect.gd -- --level=sunny_forest --script-fox

# PNG comparison self-test
python3 scripts/compare_screenshots.py --self-test
```

## How it works

### Test harness (`game/tests/platform/`)

Each visual test extends `TestRunner` (a `SceneTree` script) and overrides
`_build_timeline()` to return an `InputTimeline`. The timeline specifies:

- **Input entries**: scripted `InputFrame` values (axis, jump, action) for each
  hero (peer_id 1 = rabbit, peer_id 2 = fox) over a frame range.
- **Captures**: screenshot names at specific frames.
- **Assertions**: checks at specific frames or at the end (position, score,
  gate state, hearts, errors, alive, finished, bubble count, ammo).

The harness loads the level into a `SubViewport` (1340x800), uses engine-driven
physics with an `_InputInjector` helper node to apply scripted input after the
level's `route_control_frames` overwrites the local hero, and captures
screenshots via `SubViewport.get_texture().get_image().save_png()`.

Visual `_process` animations are frozen for deterministic rendering. Physics
runs at the engine's default tick rate with `max_physics_steps_per_frame(1)` to
cap catch-up bursts, and physics ticks per second is set to 1 during the render
await to prevent extra ticks. This produces byte-for-byte identical screenshots
across repeated runs.

### Orchestrator (`scripts/run_visual_tests.py`)

Discovers `game/tests/platform/test_*.gd` (excluding `test_runner.gd`), launches
each as a Godot process with `DISPLAY` inherited, collects output, scans logs
for errors, compares screenshots against baselines, and generates an HTML report
at `test-output/report.html`.

CLI options:
- `--test <name>`: run a single test
- `--update-baselines`: regenerate baselines from current run
- `--threshold <ratio>`: pixel diff threshold (default 0.02 = 2%)

If `DISPLAY` is not set, the orchestrator prints a skip message and exits 0.

### Screenshot comparison (`scripts/compare_screenshots.py`)

Stdlib-only PNG decoder/encoder. Supports RGB and RGBA 8-bit non-interlaced
PNGs with all five row filters (None, Sub, Up, Average, Paeth). Produces diff
images where changed pixels are red and unchanged pixels are white.

### Live inspection (`game/tests/platform/live_inspect.gd`)

Interactive mode that loads a level into the visible root window. The operator
drives the rabbit with the keyboard:

| Key | Action |
|-----|--------|
| A/D or Left/Right | Move left/right |
| W, Space, or Up | Jump |
| E | Context action (push, switch, pickup, fire bubble) |
| F11 | Print game state to console |
| F12 | Capture screenshot to `test-output/live/` |
| P | Toggle pause |
| ESC | Quit |

With `--script-fox`, the fox auto-walks to the right.

## Baselines

Baselines are stored in `test-output/baselines/<test_name>/<capture_name>.png`.
On first run (or with `--update-baselines`), current screenshots are saved as
new baselines. On subsequent runs, screenshots are compared against baselines;
if the changed pixel ratio exceeds the threshold, the test is marked as
`RENDER_DIFF` (regression).

Baselines are tracked in git (`.gitignore` excludes `test-output/` but preserves
`test-output/baselines/`). Run `--update-baselines` only after intentional
visual changes.

## Reading the HTML report

Open `test-output/report.html` in a browser. Each test has a badge (pass/fail),
baseline/current/diff thumbnails, changed-pixel percentages, state snapshots
(hero positions, score, hearts), assertion results, alerts, and error-log
excerpts.

## Integration with `test_all.sh`

`scripts/test_all.sh` excludes `game/tests/platform/*` from the headless test
loop (visual tests cannot run headless). At the end, it runs
`python3 scripts/run_visual_tests.py` only if `DISPLAY` is set; otherwise it
prints a skip message.

## Available tests

| Test | Description |
|------|-------------|
| `sunny_forest_walk` | Both heroes walk right through the meadow |
| `sunny_forest_gates` | Teamwork gate: fox pushes fallen log, rabbit hits overhead switch |
| `sunny_forest_full` | Stars, both gates, bubble power-up, fire bubble, finish level |
