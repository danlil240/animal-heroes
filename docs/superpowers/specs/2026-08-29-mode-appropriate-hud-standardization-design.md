# Mode-Appropriate HUD Standardization — Design

**Date:** 2026-08-29
**Status:** Approved (brainstorming complete)
**Parent initiative:** Visual improvement — bring other levels up to the sunny_forest visual standard.
**Sub-project:** A. HUD standardization (first of several sub-projects; backgrounds, collectibles, and robot_boss arena framing are later cycles).

## Goal

Give every level a readable, mode-appropriate gameplay HUD so players always see the state that determines the outcome of their mode. Today only `sunny_forest` has a HUD; the other six levels show nothing.

## Non-goals (this cycle)

- Themed backgrounds for the competitive arenas (sub-project B).
- Missing collectible visuals (sub-project C).
- robot_boss arena framing / own background (sub-project D).
- Context-action prompts for `crystal_caves` switches. Its switch model (`activated` signal, not the `sunny_interactable` group + `ActionResolver`) differs from sunny_forest's, so wiring the context prompt needs its own `_present_level` + resolver work. Deferred to a follow-up; the HUD still shows score/hearts.
- Hearts in competitive HUDs. Competitive modes do not track health as a win condition (bubble_bounce only knockbacks; the arenas have no enemies). Showing hearts would mislead.

## Architecture

Three HUD families, each a focused component with a typed `render()` contract. No shared "uber-HUD". Levels instantiate the right component(s) in their `HUD` CanvasLayer.

### Coop HUD (existing, reused)

`GameplayHud` (`game/ui/gameplay_hud.gd` + `.tscn`) already exists and is driven by `CoopLevel._render_gameplay_hud()`, which calls `hud.render(team_score.total, rabbit.hearts, fox.hearts, bubble_ammo.remaining(local_peer_id))`. The component hides the ammo row when `local_ammo == 0` and hides the context panel until `show_context()` is called.

Rolling it out to the remaining coop levels is a scene edit only — the base-class wiring already calls `render()` and tolerates a missing HUD node (it null-guards). No `gameplay_hud.gd` changes.

### Boss status overlay (new)

`BossStatusOverlay` (`game/ui/boss_status_overlay.gd` + `.tscn`) — a compact `Control` anchored top-center, *below* the coop score row. Composed alongside `GameplayHud` in robot_boss; it does not replace the coop HUD (hearts and team score still matter in the boss fight).

Contract:
```gdscript
func render(phase: String, cycle_count: int, phase_seconds_left: float) -> void
```

Contents:
- Phase label with a friendly Hebrew label for each `RobotBoss` phase: `intro`, `avoid`, `switches`, `weak_point`, `defeated`.
- Cycle progress `cycle_count / REQUIRED_CYCLES` (e.g. `1/3`).
- Phase timer bar — a `ColorRect` whose width is a fraction of `phase_seconds_left / PHASE_TIME_LIMIT`. No shader; a plain ColorRect scaled by tween or direct width assignment.

`robot_boss.gd._step_level` calls `overlay.render(boss.phase, boss.cycle_count, RobotBoss.PHASE_TIME_LIMIT - boss.phase_timer)` each tick.

### Competitive HUDs (new, three separate components)

Each is `game/ui/<name>_hud.gd` + `.tscn`, themed via the existing `game_theme.tres`, built from `Label`/`ColorRect` nodes only (SM-T220-safe, no shaders, no embedded rasters). No hearts. No shared base class — the three render signatures differ by design.

#### BubbleBounceHud
```gdscript
func render(time_remaining: float, host_score: int, guest_score: int, local_ammo: int) -> void
```
- Top center: countdown `M:SS` from `time_remaining`.
- Left: host peer score with a peer label.
- Right: guest peer score with a peer label.
- Bottom-right: local ammo pips (reuse the `◯` marks pattern from `GameplayHud`), hidden when 0.

#### StarRaceHud
```gdscript
func render(host_progress: int, guest_progress: int, host_finished: bool, guest_finished: bool) -> void
```
- Left: host checkpoint progress `N/4` with a `✓` when `host_finished`.
- Right: guest checkpoint progress `N/4` with a `✓` when `guest_finished`.
- No countdown — the race is first-finisher + grace period, not a player-facing timer.

#### TreasureDashHud
```gdscript
func render(time_remaining: float, host_score: int, guest_score: int) -> void
```
- Top center: countdown `M:SS` from `time_remaining`.
- Left: host score.
- Right: guest score.

### Wiring

- **Coop levels:** add a `GameplayHud` instance to each level's `HUD` node (ext_resource + node, matching sunny_forest's layout). `CoopLevel._render_gameplay_hud()` already drives it.
- **robot_boss:** add `GameplayHud` + `BossStatusOverlay`; add the `overlay.render(...)` call in `_step_level`.
- **Competitive arenas:** each arena gets `@onready var _hud = $HUD/<Name>Hud` and calls `_hud.render(...)` in its existing `_step_level` (bubble_bounce and treasure_dash already tick their mode there; star_race ticks `race_mode` there). `CompetitionArena` base class stays unchanged — the three distinct render signatures do not share a generic hook.

Peer identity: `CompetitionArena` sets `rabbit` meta `peer_id = HOST_PEER_ID (1)` and `fox` meta `peer_id = GUEST_PEER_ID (2)`. HUDs receive host/guest scores explicitly from the arena (which reads them off the mode object), so the HUD itself is peer-id-agnostic and renders identically on both tablets.

## Data flow

All HUDs are read-only presentations. They never mutate physics, score, ammo, or mode state. Each level's `_step_level` (coop: inherited `_render_gameplay_hud`; competitive: the new `_hud.render` call) reads authoritative state from the level/mode objects and pushes it to the HUD each tick. No new signals, no new RPCs, no autoload changes.

## Constraints honored

- No new third-party dependencies (stdlib GDScript + existing theme only).
- No `project.godot`, autoload, physics tick, or network changes.
- No permission-set changes.
- Package id `org.danlil.animalheroes` unchanged.
- Compatibility-renderer-safe (Labels + ColorRects only).
- HUDs read state only; they never delay input or mutate physics.

## Testing

- **Visual contract (extend `game/tests/integration/test_visual_target.gd`):** assert each level's HUD node exists under `HUD/` and exposes the expected `render` method:
  - `cloud_factory`, `crystal_caves`, `robot_boss` → `GameplayHud`.
  - `robot_boss` → additionally `BossStatusOverlay`.
  - `bubble_bounce_arena` → `BubbleBounceHud`.
  - `star_race_arena` → `StarRaceHud`.
  - `treasure_dash_arena` → `TreasureDashHud`.
- **Unit (new `game/tests/unit/test_competition_hud.gd`):** instantiate each competitive HUD, call `render(...)` with known values, assert label text and ammo-pip visibility. Pure logic; no full scene tree beyond the HUD instance.
- **Unit (new `game/tests/unit/test_boss_status_overlay.gd`):** instantiate `BossStatusOverlay`, call `render(...)` for each phase, assert phase label and cycle text.
- **Regression:** `bash scripts/test_all.sh` must stay green. No gameplay/physics/network changes.
- **Visual:** use the existing visual-testing platform (`scripts/run_visual_tests.py` + `game/tests/platform/live_inspect.gd`) to capture each level with the HUD visible. New baselines for the HUD-bearing captures.

## Files

### New (8)
- `game/ui/boss_status_overlay.gd`
- `game/ui/boss_status_overlay.tscn`
- `game/ui/bubble_bounce_hud.gd`
- `game/ui/bubble_bounce_hud.tscn`
- `game/ui/star_race_hud.gd`
- `game/ui/star_race_hud.tscn`
- `game/ui/treasure_dash_hud.gd`
- `game/ui/treasure_dash_hud.tscn`

### Modified (10) + 2 new test files
- `game/levels/cloud_factory.tscn` — add `GameplayHud` instance.
- `game/levels/crystal_caves.tscn` — add `GameplayHud` instance.
- `game/levels/robot_boss.tscn` — add `GameplayHud` + `BossStatusOverlay` instances.
- `game/levels/robot_boss.gd` — call `overlay.render(...)` in `_step_level`.
- `game/levels/bubble_bounce_arena.tscn` — add `BubbleBounceHud` instance.
- `game/levels/bubble_bounce_arena.gd` — `_hud.render(...)` in `_step_level`.
- `game/levels/star_race_arena.tscn` — add `StarRaceHud` instance.
- `game/levels/star_race_arena.gd` — `_hud.render(...)` in `_step_level`.
- `game/levels/treasure_dash_arena.tscn` — add `TreasureDashHud` instance.
- `game/levels/treasure_dash_arena.gd` — `_hud.render(...)` in `_step_level`.
- `game/tests/integration/test_visual_target.gd` — extend with HUD presence/signature assertions.
- `game/tests/unit/test_competition_hud.gd` — new.
- `game/tests/unit/test_boss_status_overlay.gd` — new.

### Not touched
- `game/ui/gameplay_hud.gd` / `.tscn` (coop HUD unchanged).
- Any physics, network, or autoload code.
- `project.godot`, `export_presets.cfg`, permissions.

## Acceptance

1. `bash scripts/test_all.sh` passes (exit 0).
2. Every level instantiates its mode-appropriate HUD and the visual-contract test confirms presence + `render` signature.
3. Competitive HUD unit tests confirm correct label text and ammo-pip visibility for known inputs.
4. Boss overlay unit test confirms correct phase label and cycle text for each `RobotBoss` phase.
5. `live_inspect.gd` and `run_visual_tests.py` captures show the HUD on each level; new baselines committed.
6. No gameplay, physics, network, autoload, permission, or `project.godot` changes.
