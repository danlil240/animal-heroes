# Mode-Appropriate HUD Standardization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every level a readable, mode-appropriate gameplay HUD — coop levels reuse the existing `GameplayHud`, robot_boss adds a boss phase/cycle overlay, and the three competitive arenas get distinct per-player score + timer HUDs.

**Architecture:** Four new read-only HUD components (one boss overlay + three competitive HUDs), each with a typed `render()` contract and a unit test. Coop levels get the existing `GameplayHud` via scene edits only (the `CoopLevel` base class already drives it). Each competitive arena wires its HUD in its existing `_step_level`. No shared base class for the competitive HUDs — their render signatures differ by design.

**Tech Stack:** Godot 4.7.2, typed GDScript, `game_theme.tres`, headless SceneTree tests, the existing visual-testing platform.

**Spec:** `docs/superpowers/specs/2026-08-29-mode-appropriate-hud-standardization-design.md`

## Global Constraints

- Target viewport: 1340 by 800 landscape; also verify 1024 by 600.
- Target hardware: Samsung Galaxy Tab A7 Lite Wi-Fi SM-T220; minimum 30 FPS.
- Compatibility-renderer-safe: HUDs use `Label`/`ColorRect`/`PanelContainer` only — no shaders, no blur, no embedded rasters, no dynamic lights.
- No new third-party dependencies. No `pip`/`cargo`/asset dependencies.
- Keep `physics/common/physics_ticks_per_second=30` and `TwoPlayerLevel.NET_SYNC_HZ=20.0` unchanged.
- Keep package id `org.danlil.animalheroes` unchanged.
- Keep the exact Android permission set: `INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`, `CHANGE_WIFI_MULTICAST_STATE`.
- HUDs read state only; they never mutate physics, score, ammo, mode state, or delay input.
- No hearts in competitive HUDs — health is not a win condition in those modes.
- No `project.godot`, autoload, physics, or network code changes.

## File Map

```text
game/ui/boss_status_overlay.gd          # Boss phase/cycle/timer overlay (read-only)
game/ui/boss_status_overlay.tscn
game/ui/bubble_bounce_hud.gd            # Bubble match: timer + per-player score + ammo
game/ui/bubble_bounce_hud.tscn
game/ui/star_race_hud.gd                # Race: per-player checkpoint progress + finish mark
game/ui/star_race_hud.tscn
game/ui/treasure_dash_hud.gd            # Treasure dash: timer + per-player score
game/ui/treasure_dash_hud.tscn
game/tests/unit/test_boss_status_overlay.gd   # Unit test for boss overlay
game/tests/unit/test_competition_hud.gd       # Unit test for the three competitive HUDs
```

Modified levels (scene edits + minimal `.gd` wiring calls):
- `game/levels/cloud_factory.tscn` — add `GameplayHud`.
- `game/levels/crystal_caves.tscn` — add `GameplayHud`.
- `game/levels/robot_boss.tscn` + `.gd` — add `GameplayHud` + `BossStatusOverlay`, call overlay in `_step_level`.
- `game/levels/bubble_bounce_arena.tscn` + `.gd` — add `BubbleBounceHud`, call render in `_step_level`.
- `game/levels/star_race_arena.tscn` + `.gd` — add `StarRaceHud`, call render in `_step_level`.
- `game/levels/treasure_dash_arena.tscn` + `.gd` — add `TreasureDashHud`, call render in `_step_level`.
- `game/tests/integration/test_visual_target.gd` — extend with HUD presence/signature assertions per level.

---

### Task 1: BossStatusOverlay Component

**Files:**
- Create: `game/ui/boss_status_overlay.gd`
- Create: `game/ui/boss_status_overlay.tscn`
- Create: `game/tests/unit/test_boss_status_overlay.gd`

**Interfaces:**
- Produces: `BossStatusOverlay.render(phase: String, cycle_count: int, phase_seconds_left: float) -> void`
- Produces: scene node paths `PhaseLabel`, `CycleLabel`, `TimerBar` (a `ColorRect`), `TimerTrack` (the full-width background `ColorRect`).
- `phase` is one of `RobotBoss.INTRO/AVOID/SWITCHES/WEAK_POINT/DEFEATED`.
- `cycle_count` is 0..3; display as `cycle_count + 1` clamped to `REQUIRED_CYCLES` when not defeated, or `REQUIRED_CYCLES` when defeated.
- `phase_seconds_left` drives the `TimerBar` width as a fraction of `RobotBoss.PHASE_TIME_LIMIT` (45.0), clamped 0..1.

- [ ] **Step 1: Write the failing unit test**

Create `game/tests/unit/test_boss_status_overlay.gd`:

```gdscript
extends SceneTree

const PHASE_TIME_LIMIT := 45.0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load("res://ui/boss_status_overlay.tscn")
	if scene == null:
		_fail("boss status overlay scene must load")
		return
	var overlay = scene.instantiate()
	root.add_child(overlay)
	await process_frame
	for required in ["PhaseLabel", "CycleLabel", "TimerBar", "TimerTrack"]:
		if overlay.get_node_or_null(required) == null:
			_fail("boss overlay must expose node %s" % required)
			return
	overlay.render("avoid", 0, 30.0)
	if overlay.get_node("PhaseLabel").text.is_empty():
		_fail("boss overlay must show a non-empty phase label for avoid")
		return
	if overlay.get_node("CycleLabel").text != "1/3":
		_fail("boss overlay cycle must read 1/3 for cycle_count 0, got %s" % overlay.get_node("CycleLabel").text)
		return
	var bar: ColorRect = overlay.get_node("TimerBar")
	var track: ColorRect = overlay.get_node("TimerTrack")
	var expected_fraction := clampf(30.0 / PHASE_TIME_LIMIT, 0.0, 1.0)
	if absf(bar.size.x - track.size.x * expected_fraction) > 1.0:
		_fail("boss overlay timer bar must reflect seconds left fraction")
		return
	overlay.render("defeated", 3, 0.0)
	if overlay.get_node("CycleLabel").text != "3/3":
		_fail("boss overlay cycle must read 3/3 when defeated, got %s" % overlay.get_node("CycleLabel").text)
		return
	overlay.queue_free()
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `godot --headless --path game -s res://tests/unit/test_boss_status_overlay.gd`
Expected: FAIL with "boss status overlay scene must load".

- [ ] **Step 3: Implement the overlay script**

Create `game/ui/boss_status_overlay.gd`:

```gdscript
class_name BossStatusOverlay
extends Control

## Read-only boss-fight status: friendly phase label, cycle progress, and a
## phase timer bar. Composed alongside GameplayHud in the robot boss arena.

const REQUIRED_CYCLES := 3
const PHASE_TIME_LIMIT := 45.0

const PHASE_LABELS := {
	"intro": "הכנה",
	"avoid": "התחמקות",
	"switches": "הפעל מתגים",
	"weak_point": "פגע בנקודה",
	"defeated": "ניצחון!",
}


func _ready() -> void:
	render("intro", 0, PHASE_TIME_LIMIT)


func render(phase: String, cycle_count: int, phase_seconds_left: float) -> void:
	$PhaseLabel.text = String(PHASE_LABELS.get(phase, phase))
	var display_cycle := mini(cycle_count + 1, REQUIRED_CYCLES) if phase != "defeated" else REQUIRED_CYCLES
	$CycleLabel.text = "%d/%d" % [display_cycle, REQUIRED_CYCLES]
	var fraction := clampf(phase_seconds_left / PHASE_TIME_LIMIT, 0.0, 1.0)
	var track: ColorRect = $TimerTrack
	var bar: ColorRect = $TimerBar
	bar.size.x = track.size.x * fraction
```

- [ ] **Step 4: Build the overlay scene**

Create `game/ui/boss_status_overlay.tscn`:

```text
[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://ui/boss_status_overlay.gd" id="1_overlay"]
[ext_resource type="Theme" path="res://theme/game_theme.tres" id="2_theme"]

[node name="BossStatusOverlay" type="Control"]
layout_mode = 3
anchors_preset = 7
anchor_left = 0.5
anchor_right = 0.5
offset_left = -200.0
offset_top = 92.0
offset_right = 200.0
offset_bottom = 168.0
grow_horizontal = 2
mouse_filter = 2
theme = ExtResource("2_theme")
script = ExtResource("1_overlay")

[node name="PhaseLabel" type="Label" parent="."]
layout_mode = 1
anchors_preset = 10
anchor_right = 1.0
offset_top = 0.0
offset_bottom = 40.0
theme_override_colors/font_color = Color(1, 0.83, 0.24, 1)
theme_override_colors/font_outline_color = Color(0.09, 0.16, 0.29, 1)
theme_override_constants/outline_size = 8
theme_override_font_sizes/font_size = 30
text = "הכנה"
horizontal_alignment = 1

[node name="CycleLabel" type="Label" parent="."]
layout_mode = 1
anchors_preset = 10
anchor_right = 1.0
offset_top = 38.0
offset_bottom = 70.0
theme_override_colors/font_color = Color(0.86, 0.97, 1.0, 1)
theme_override_colors/font_outline_color = Color(0.09, 0.16, 0.29, 1)
theme_override_constants/outline_size = 6
theme_override_font_sizes/font_size = 24
text = "1/3"
horizontal_alignment = 1

[node name="TimerTrack" type="ColorRect" parent="."]
layout_mode = 1
anchors_preset = 10
anchor_right = 1.0
offset_top = 72.0
offset_bottom = 80.0
color = Color(0.09, 0.16, 0.29, 0.6)

[node name="TimerBar" type="ColorRect" parent="."]
layout_mode = 1
anchors_preset = 10
offset_top = 72.0
offset_bottom = 80.0
color = Color(1, 0.83, 0.24, 1)
```

Note: `TimerBar` width is set by `render()`; its initial `size.x` is 0 and grows to `TimerTrack.size.x * fraction`. Both rects share the same top/bottom so the bar sits inside the track.

- [ ] **Step 5: Run the test to verify it passes**

Run: `godot --headless --path game -s res://tests/unit/test_boss_status_overlay.gd`
Expected: PASS (exit 0).

- [ ] **Step 6: Commit**

```bash
git add game/ui/boss_status_overlay.gd game/ui/boss_status_overlay.tscn game/tests/unit/test_boss_status_overlay.gd
git commit -m "feat: add boss status overlay component"
```

---

### Task 2: BubbleBounceHud Component

**Files:**
- Create: `game/ui/bubble_bounce_hud.gd`
- Create: `game/ui/bubble_bounce_hud.tscn`
- Create: `game/tests/unit/test_competition_hud.gd` (this task adds the bubble bounce cases; Tasks 3 and 4 extend the same file)

**Interfaces:**
- Produces: `BubbleBounceHud.render(time_remaining: float, host_score: int, guest_score: int, local_ammo: int) -> void`
- Produces: scene node paths `Timer`, `HostScore`, `GuestScore`, `Ammo/Marks` (5 `Label` children like `GameplayHud`).
- `time_remaining` formats as `M:SS` (e.g. `3:00`, `0:07`).
- Host = Riki (rabbit, peer 1, left side); Guest = Foxy (fox, peer 2, right side).

- [ ] **Step 1: Write the failing unit test**

Create `game/tests/unit/test_competition_hud.gd`:

```gdscript
extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if not await _test_bubble_bounce_hud():
		return
	quit(0)


func _test_bubble_bounce_hud() -> bool:
	var scene: PackedScene = load("res://ui/bubble_bounce_hud.tscn")
	if scene == null:
		return _fail_bool("bubble bounce HUD scene must load")
	var hud = scene.instantiate()
	root.add_child(hud)
	await process_frame
	hud.render(180.0, 3, 1, 2)
	if hud.get_node("Timer").text != "3:00":
		return _fail_bool("bubble bounce HUD timer must format M:SS, got %s" % hud.get_node("Timer").text)
	if hud.get_node("HostScore").text != "3":
		return _fail_bool("bubble bounce HUD must show host score")
	if hud.get_node("GuestScore").text != "1":
		return _fail_bool("bubble bounce HUD must show guest score")
	var marks: Array[Node] = hud.get_node("Ammo/Marks").get_children()
	if marks.size() != 5:
		return _fail_bool("bubble bounce HUD must precreate five ammo marks")
	for index in marks.size():
		if marks[index].visible != (index < 2):
			return _fail_bool("bubble bounce HUD ammo marks must match local ammo")
	hud.render(7.0, 0, 0, 0)
	if hud.get_node("Timer").text != "0:07":
		return _fail_bool("bubble bounce HUD timer must show seconds under ten, got %s" % hud.get_node("Timer").text)
	if hud.get_node("Ammo").visible:
		return _fail_bool("bubble bounce HUD ammo must hide when empty")
	hud.queue_free()
	return true


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _fail_bool(message: String) -> bool:
	_fail(message)
	return false
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `godot --headless --path game -s res://tests/unit/test_competition_hud.gd`
Expected: FAIL with "bubble bounce HUD scene must load".

- [ ] **Step 3: Implement the HUD script**

Create `game/ui/bubble_bounce_hud.gd`:

```gdscript
class_name BubbleBounceHud
extends Control

## Friendly bubble match HUD: countdown timer, per-player scores, and the
## local player's bubble ammo. Read-only; never mutates match state.


func _ready() -> void:
	$Ammo.visible = false


func render(time_remaining: float, host_score: int, guest_score: int, local_ammo: int) -> void:
	$Timer.text = _format_time(time_remaining)
	$HostScore.text = str(maxi(host_score, 0))
	$GuestScore.text = str(maxi(guest_score, 0))
	var clamped_ammo := clampi(local_ammo, 0, 5)
	var marks: Array[Node] = $Ammo/Marks.get_children()
	for index in marks.size():
		marks[index].visible = index < clamped_ammo
	$Ammo.visible = clamped_ammo > 0


func _format_time(seconds: float) -> String:
	var total := maxi(int(roundf(seconds)), 0)
	var minutes := total / 60
	var secs := total % 60
	return "%d:%02d" % [minutes, secs]
```

- [ ] **Step 4: Build the HUD scene**

Create `game/ui/bubble_bounce_hud.tscn`:

```text
[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://ui/bubble_bounce_hud.gd" id="1_hud"]
[ext_resource type="Theme" path="res://theme/game_theme.tres" id="2_theme"]

[node name="BubbleBounceHud" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
theme = ExtResource("2_theme")
script = ExtResource("1_hud")

[node name="Timer" type="Label" parent="."]
layout_mode = 1
anchors_preset = 10
anchor_right = 1.0
offset_top = 18.0
offset_bottom = 64.0
theme_override_colors/font_color = Color(1, 0.83, 0.24, 1)
theme_override_colors/font_outline_color = Color(0.09, 0.16, 0.29, 1)
theme_override_constants/outline_size = 8
theme_override_font_sizes/font_size = 38
text = "3:00"
horizontal_alignment = 1

[node name="HostScore" type="Label" parent="."]
layout_mode = 1
anchors_preset = 9
anchor_bottom = 1.0
offset_left = 24.0
offset_top = 18.0
offset_right = 240.0
offset_bottom = 64.0
grow_horizontal = 1
theme_override_colors/font_color = Color(1, 0.42, 0.47, 1)
theme_override_colors/font_outline_color = Color(0.09, 0.16, 0.29, 1)
theme_override_constants/outline_size = 8
theme_override_font_sizes/font_size = 34
text = "0"

[node name="GuestScore" type="Label" parent="."]
layout_mode = 1
anchors_preset = 9
anchor_right = 1.0
anchor_bottom = 1.0
offset_left = -240.0
offset_top = 18.0
offset_right = -24.0
offset_bottom = 64.0
grow_horizontal = 0
theme_override_colors/font_color = Color(1, 0.42, 0.47, 1)
theme_override_colors/font_outline_color = Color(0.09, 0.16, 0.29, 1)
theme_override_constants/outline_size = 8
theme_override_font_sizes/font_size = 34
text = "0"
horizontal_alignment = 2

[node name="Ammo" type="VBoxContainer" parent="."]
layout_mode = 1
anchors_preset = 3
anchor_left = 1.0
anchor_top = 1.0
anchor_right = 1.0
anchor_bottom = 1.0
offset_left = -154.0
offset_top = -214.0
offset_right = -24.0
offset_bottom = -164.0
grow_horizontal = 0
grow_vertical = 0

[node name="Marks" type="HBoxContainer" parent="Ammo"]
layout_mode = 2
theme_override_constants/separation = 4

[node name="Bubble1" type="Label" parent="Ammo/Marks"]
layout_mode = 2
theme_override_font_sizes/font_size = 22
text = "◯"

[node name="Bubble2" type="Label" parent="Ammo/Marks"]
layout_mode = 2
theme_override_font_sizes/font_size = 22
text = "◯"

[node name="Bubble3" type="Label" parent="Ammo/Marks"]
layout_mode = 2
theme_override_font_sizes/font_size = 22
text = "◯"

[node name="Bubble4" type="Label" parent="Ammo/Marks"]
layout_mode = 2
theme_override_font_sizes/font_size = 22
text = "◯"

[node name="Bubble5" type="Label" parent="Ammo/Marks"]
layout_mode = 2
theme_override_font_sizes/font_size = 22
text = "◯"
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `godot --headless --path game -s res://tests/unit/test_competition_hud.gd`
Expected: PASS (exit 0).

- [ ] **Step 6: Commit**

```bash
git add game/ui/bubble_bounce_hud.gd game/ui/bubble_bounce_hud.tscn game/tests/unit/test_competition_hud.gd
git commit -m "feat: add bubble bounce competitive HUD"
```

---

### Task 3: StarRaceHud Component

**Files:**
- Create: `game/ui/star_race_hud.gd`
- Create: `game/ui/star_race_hud.tscn`
- Modify: `game/tests/unit/test_competition_hud.gd` (add star race cases)

**Interfaces:**
- Produces: `StarRaceHud.render(host_progress: int, guest_progress: int, host_finished: bool, guest_finished: bool) -> void`
- Produces: scene node paths `HostProgress`, `GuestProgress`.
- Progress displays as `N/4`; when finished, appends ` ✓`.
- `StarRaceMode.CHECKPOINTS_PER_ROUTE` is 4.

- [ ] **Step 1: Write the failing unit test**

Add this method to `game/tests/unit/test_competition_hud.gd`, and call it from `_run()` before `quit(0)`:

```gdscript
func _run() -> void:
	if not await _test_bubble_bounce_hud():
		return
	if not await _test_star_race_hud():
		return
	quit(0)


func _test_star_race_hud() -> bool:
	var scene: PackedScene = load("res://ui/star_race_hud.tscn")
	if scene == null:
		return _fail_bool("star race HUD scene must load")
	var hud = scene.instantiate()
	root.add_child(hud)
	await process_frame
	hud.render(2, 4, false, true)
	if hud.get_node("HostProgress").text != "2/4":
		return _fail_bool("star race HUD host progress must read N/4, got %s" % hud.get_node("HostProgress").text)
	if hud.get_node("GuestProgress").text != "4/4 ✓":
		return _fail_bool("star race HUD must append checkmark when finished, got %s" % hud.get_node("GuestProgress").text)
	hud.render(4, 4, true, true)
	if hud.get_node("HostProgress").text != "4/4 ✓":
		return _fail_bool("star race HUD host must show checkmark when finished, got %s" % hud.get_node("HostProgress").text)
	hud.queue_free()
	return true
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `godot --headless --path game -s res://tests/unit/test_competition_hud.gd`
Expected: FAIL with "star race HUD scene must load".

- [ ] **Step 3: Implement the HUD script**

Create `game/ui/star_race_hud.gd`:

```gdscript
class_name StarRaceHud
extends Control

## Friendly race HUD: per-player checkpoint progress with a finish mark.
## Read-only; never mutates race state.

const CHECKPOINTS_PER_ROUTE := 4


func render(host_progress: int, guest_progress: int, host_finished: bool, guest_finished: bool) -> void:
	$HostProgress.text = _progress_text(host_progress, host_finished)
	$GuestProgress.text = _progress_text(guest_progress, guest_finished)


func _progress_text(progress: int, finished: bool) -> String:
	var clamped := clampi(progress, 0, CHECKPOINTS_PER_ROUTE)
	var base := "%d/%d" % [clamped, CHECKPOINTS_PER_ROUTE]
	if finished:
		base += " ✓"
	return base
```

- [ ] **Step 4: Build the HUD scene**

Create `game/ui/star_race_hud.tscn`:

```text
[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://ui/star_race_hud.gd" id="1_hud"]
[ext_resource type="Theme" path="res://theme/game_theme.tres" id="2_theme"]

[node name="StarRaceHud" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
theme = ExtResource("2_theme")
script = ExtResource("1_hud")

[node name="HostProgress" type="Label" parent="."]
layout_mode = 1
anchors_preset = 9
anchor_bottom = 1.0
offset_left = 24.0
offset_top = 18.0
offset_right = 280.0
offset_bottom = 64.0
grow_horizontal = 1
theme_override_colors/font_color = Color(1, 0.42, 0.47, 1)
theme_override_colors/font_outline_color = Color(0.09, 0.16, 0.29, 1)
theme_override_constants/outline_size = 8
theme_override_font_sizes/font_size = 34
text = "0/4"

[node name="GuestProgress" type="Label" parent="."]
layout_mode = 1
anchors_preset = 9
anchor_right = 1.0
anchor_bottom = 1.0
offset_left = -280.0
offset_top = 18.0
offset_right = -24.0
offset_bottom = 64.0
grow_horizontal = 0
theme_override_colors/font_color = Color(1, 0.42, 0.47, 1)
theme_override_colors/font_outline_color = Color(0.09, 0.16, 0.29, 1)
theme_override_constants/outline_size = 8
theme_override_font_sizes/font_size = 34
text = "0/4"
horizontal_alignment = 2
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `godot --headless --path game -s res://tests/unit/test_competition_hud.gd`
Expected: PASS (exit 0).

- [ ] **Step 6: Commit**

```bash
git add game/ui/star_race_hud.gd game/ui/star_race_hud.tscn game/tests/unit/test_competition_hud.gd
git commit -m "feat: add star race competitive HUD"
```

---

### Task 4: TreasureDashHud Component

**Files:**
- Create: `game/ui/treasure_dash_hud.gd`
- Create: `game/ui/treasure_dash_hud.tscn`
- Modify: `game/tests/unit/test_competition_hud.gd` (add treasure dash cases)

**Interfaces:**
- Produces: `TreasureDashHud.render(time_remaining: float, host_score: int, guest_score: int) -> void`
- Produces: scene node paths `Timer`, `HostScore`, `GuestScore`.
- Timer formats as `M:SS` (same as `BubbleBounceHud._format_time`).

- [ ] **Step 1: Write the failing unit test**

Add this method to `game/tests/unit/test_competition_hud.gd`, and call it from `_run()` before `quit(0)`:

```gdscript
func _run() -> void:
	if not await _test_bubble_bounce_hud():
		return
	if not await _test_star_race_hud():
		return
	if not await _test_treasure_dash_hud():
		return
	quit(0)


func _test_treasure_dash_hud() -> bool:
	var scene: PackedScene = load("res://ui/treasure_dash_hud.tscn")
	if scene == null:
		return _fail_bool("treasure dash HUD scene must load")
	var hud = scene.instantiate()
	root.add_child(hud)
	await process_frame
	hud.render(180.0, 12, 7)
	if hud.get_node("Timer").text != "3:00":
		return _fail_bool("treasure dash HUD timer must format M:SS, got %s" % hud.get_node("Timer").text)
	if hud.get_node("HostScore").text != "12":
		return _fail_bool("treasure dash HUD must show host score, got %s" % hud.get_node("HostScore").text)
	if hud.get_node("GuestScore").text != "7":
		return _fail_bool("treasure dash HUD must show guest score, got %s" % hud.get_node("GuestScore").text)
	hud.queue_free()
	return true
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `godot --headless --path game -s res://tests/unit/test_competition_hud.gd`
Expected: FAIL with "treasure dash HUD scene must load".

- [ ] **Step 3: Implement the HUD script**

Create `game/ui/treasure_dash_hud.gd`:

```gdscript
class_name TreasureDashHud
extends Control

## Timed collection match HUD: countdown timer and per-player scores.
## Read-only; never mutates match state.


func render(time_remaining: float, host_score: int, guest_score: int) -> void:
	$Timer.text = _format_time(time_remaining)
	$HostScore.text = str(maxi(host_score, 0))
	$GuestScore.text = str(maxi(guest_score, 0))


func _format_time(seconds: float) -> String:
	var total := maxi(int(roundf(seconds)), 0)
	var minutes := total / 60
	var secs := total % 60
	return "%d:%02d" % [minutes, secs]
```

- [ ] **Step 4: Build the HUD scene**

Create `game/ui/treasure_dash_hud.tscn`:

```text
[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://ui/treasure_dash_hud.gd" id="1_hud"]
[ext_resource type="Theme" path="res://theme/game_theme.tres" id="2_theme"]

[node name="TreasureDashHud" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
theme = ExtResource("2_theme")
script = ExtResource("1_hud")

[node name="Timer" type="Label" parent="."]
layout_mode = 1
anchors_preset = 10
anchor_right = 1.0
offset_top = 18.0
offset_bottom = 64.0
theme_override_colors/font_color = Color(1, 0.83, 0.24, 1)
theme_override_colors/font_outline_color = Color(0.09, 0.16, 0.29, 1)
theme_override_constants/outline_size = 8
theme_override_font_sizes/font_size = 38
text = "3:00"
horizontal_alignment = 1

[node name="HostScore" type="Label" parent="."]
layout_mode = 1
anchors_preset = 9
anchor_bottom = 1.0
offset_left = 24.0
offset_top = 18.0
offset_right = 240.0
offset_bottom = 64.0
grow_horizontal = 1
theme_override_colors/font_color = Color(1, 0.42, 0.47, 1)
theme_override_colors/font_outline_color = Color(0.09, 0.16, 0.29, 1)
theme_override_constants/outline_size = 8
theme_override_font_sizes/font_size = 34
text = "0"

[node name="GuestScore" type="Label" parent="."]
layout_mode = 1
anchors_preset = 9
anchor_right = 1.0
anchor_bottom = 1.0
offset_left = -240.0
offset_top = 18.0
offset_right = -24.0
offset_bottom = 64.0
grow_horizontal = 0
theme_override_colors/font_color = Color(1, 0.42, 0.47, 1)
theme_override_colors/font_outline_color = Color(0.09, 0.16, 0.29, 1)
theme_override_constants/outline_size = 8
theme_override_font_sizes/font_size = 34
text = "0"
horizontal_alignment = 2
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `godot --headless --path game -s res://tests/unit/test_competition_hud.gd`
Expected: PASS (exit 0).

- [ ] **Step 6: Commit**

```bash
git add game/ui/treasure_dash_hud.gd game/ui/treasure_dash_hud.tscn game/tests/unit/test_competition_hud.gd
git commit -m "feat: add treasure dash competitive HUD"
```

---

### Task 5: Wire GameplayHud into Coop Levels (cloud_factory, crystal_caves)

**Files:**
- Modify: `game/levels/cloud_factory.tscn`
- Modify: `game/levels/crystal_caves.tscn`
- Modify: `game/tests/integration/test_visual_target.gd`

**Interfaces:**
- Consumes: `GameplayHud` (`res://ui/gameplay_hud.tscn`) — already driven by `CoopLevel._render_gameplay_hud()`.
- No `.gd` changes needed — `CoopLevel._render_gameplay_hud()` already null-guards and calls `hud.render(team_score.total, rabbit.hearts, fox.hearts, bubble_ammo.remaining(local_peer_id))`.

- [ ] **Step 1: Write the failing visual-contract test**

Add this method to `game/tests/integration/test_visual_target.gd`, and call it from `_run()` after `_test_gameplay_hud_presentation()` and before `_test_complete_arena_composition()`:

```gdscript
func _test_coop_hud_presence() -> bool:
	for level_path in [
		"res://levels/cloud_factory.tscn",
		"res://levels/crystal_caves.tscn",
		"res://levels/robot_boss.tscn",
	]:
		var level = load(level_path).instantiate()
		root.add_child(level)
		await process_frame
		var hud = level.get_node_or_null("HUD/GameplayHud")
		if hud == null:
			level.queue_free()
			return _fail_bool("%s must compose the coop GameplayHud" % level_path.get_file())
		if not hud.has_method("render"):
			level.queue_free()
			return _fail_bool("%s GameplayHud must expose render()" % level_path.get_file())
		level.queue_free()
	return true
```

Update `_run()` to call it:

```gdscript
	if not _test_gameplay_hud_presentation():
		return
	if not await _test_coop_hud_presence():
		return
	if not _test_complete_arena_composition():
		return
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `godot --headless --path game -s res://tests/integration/test_visual_target.gd`
Expected: FAIL with "cloud_factory.tscn must compose the coop GameplayHud".

- [ ] **Step 3: Add GameplayHud to cloud_factory.tscn**

In `game/levels/cloud_factory.tscn`, add the ext_resource after the existing `gameplay_hud`-less resource block. The file currently has `load_steps=27`. Add this ext_resource (the `id` must be unique — use the next available; the existing resources use ids `1_factory` through `16_exit_visual`, so use `17_gameplay_hud`):

```text
[ext_resource type="PackedScene" path="res://ui/gameplay_hud.tscn" id="17_gameplay_hud"]
```

Bump `load_steps` from 27 to 28.

Then add the HUD node inside the `HUD` CanvasLayer, after `TouchControls`:

```text
[node name="GameplayHud" parent="HUD" instance=ExtResource("17_gameplay_hud")]
```

- [ ] **Step 4: Add GameplayHud to crystal_caves.tscn**

In `game/levels/crystal_caves.tscn`, add the ext_resource (existing ids go `1_caves` through `18_boulder_visual`, so use `19_gameplay_hud`):

```text
[ext_resource type="PackedScene" path="res://ui/gameplay_hud.tscn" id="19_gameplay_hud"]
```

Bump `load_steps` from 28 to 29.

Then add the HUD node inside the `HUD` CanvasLayer, after `TouchControls`:

```text
[node name="GameplayHud" parent="HUD" instance=ExtResource("19_gameplay_hud")]
```

- [ ] **Step 5: Run the focused test to verify it passes**

Run: `godot --headless --path game -s res://tests/integration/test_visual_target.gd`
Expected: still FAIL on `robot_boss.tscn must compose the coop GameplayHud` (robot_boss is wired in Task 6). The cloud_factory and crystal_caves assertions must pass.

To verify just the coop levels without the robot_boss failure blocking, temporarily run the levels individually via `live_inspect.gd`:

```bash
godot --path game -s res://tests/platform/live_inspect.gd --level=cloud_factory
# ESC to quit; confirm the HUD (score + hearts) is visible at top.
godot --path game -s res://tests/platform/live_inspect.gd --level=crystal_caves
# ESC to quit; confirm the HUD is visible.
```

- [ ] **Step 6: Commit**

```bash
git add game/levels/cloud_factory.tscn game/levels/crystal_caves.tscn game/tests/integration/test_visual_target.gd
git commit -m "feat: add coop GameplayHud to cloud factory and crystal caves"
```

---

### Task 6: Wire GameplayHud + BossStatusOverlay into robot_boss

**Files:**
- Modify: `game/levels/robot_boss.tscn`
- Modify: `game/levels/robot_boss.gd`
- Modify: `game/tests/integration/test_visual_target.gd`

**Interfaces:**
- Consumes: `GameplayHud` (driven by `CoopLevel._render_gameplay_hud()`), `BossStatusOverlay` (Task 1).
- Consumes: `RobotBoss.phase`, `RobotBoss.cycle_count`, `RobotBoss.phase_timer`, `RobotBoss.PHASE_TIME_LIMIT`, `RobotBoss.DEFEATED`.

- [ ] **Step 1: Write the failing visual-contract test**

Add this method to `game/tests/integration/test_visual_target.gd`, and call it from `_run()` after `_test_coop_hud_presence()`:

```gdscript
func _test_boss_overlay_presence() -> bool:
	var level = load("res://levels/robot_boss.tscn").instantiate()
	root.add_child(level)
	await process_frame
	var overlay = level.get_node_or_null("HUD/BossStatusOverlay")
	if overlay == null:
		level.queue_free()
		return _fail_bool("robot_boss must compose the BossStatusOverlay")
	if not overlay.has_method("render"):
		level.queue_free()
		return _fail_bool("BossStatusOverlay must expose render()")
	level.queue_free()
	return true
```

Update `_run()`:

```gdscript
	if not await _test_coop_hud_presence():
		return
	if not await _test_boss_overlay_presence():
		return
	if not _test_complete_arena_composition():
		return
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `godot --headless --path game -s res://tests/integration/test_visual_target.gd`
Expected: FAIL — either on `robot_boss.tscn must compose the coop GameplayHud` (from `_test_coop_hud_presence`) or `robot_boss must compose the BossStatusOverlay` (from `_test_boss_overlay_presence`).

- [ ] **Step 3: Add GameplayHud + BossStatusOverlay to robot_boss.tscn**

In `game/levels/robot_boss.tscn`, add two ext_resources (existing ids go `1_boss` through `10_boss_visual`, so use `11_gameplay_hud` and `12_boss_overlay`):

```text
[ext_resource type="PackedScene" path="res://ui/gameplay_hud.tscn" id="11_gameplay_hud"]
[ext_resource type="PackedScene" path="res://ui/boss_status_overlay.tscn" id="12_boss_overlay"]
```

Bump `load_steps` from 16 to 18.

Then add both nodes inside the `HUD` CanvasLayer, after `TouchControls`:

```text
[node name="GameplayHud" parent="HUD" instance=ExtResource("11_gameplay_hud")]

[node name="BossStatusOverlay" parent="HUD" instance=ExtResource("12_boss_overlay")]
```

- [ ] **Step 4: Wire the overlay render call in robot_boss.gd**

In `game/levels/robot_boss.gd`, add an `@onready` reference and call `render` in `_step_level`. The full updated file:

```gdscript
class_name RobotBossArena
extends CoopLevel

## Cooperative boss arena: the comical robot's deterministic phase machine runs
## on the host tick, and defeating it completes the campaign.

const RobotBoss = preload("res://world/robot_boss.gd")

var boss: RobotBoss = null

@onready var _boss_overlay = $HUD/BossStatusOverlay


func _setup_coop_level() -> void:
	boss = RobotBoss.new()
	boss.begin(true)
	boss.defeated.connect(_on_boss_defeated)


func _step_level(delta: float) -> void:
	boss.host_step(delta)
	_boss_overlay.render(boss.phase, boss.cycle_count, RobotBoss.PHASE_TIME_LIMIT - boss.phase_timer)


func activate_switch(switch_id: int) -> void:
	boss.activate_switch(switch_id)


func hit_weak_point(weak_point_id: int) -> void:
	boss.hit_weak_point(weak_point_id)


func _on_boss_defeated() -> void:
	coop_mode.complete_campaign()
```

- [ ] **Step 5: Run the focused test to verify it passes**

Run: `godot --headless --path game -s res://tests/integration/test_visual_target.gd`
Expected: PASS (exit 0) — all assertions including coop HUD presence and boss overlay presence.

- [ ] **Step 6: Commit**

```bash
git add game/levels/robot_boss.tscn game/levels/robot_boss.gd game/tests/integration/test_visual_target.gd
git commit -m "feat: add coop HUD and boss status overlay to robot boss"
```

---

### Task 7: Wire BubbleBounceHud into bubble_bounce_arena

**Files:**
- Modify: `game/levels/bubble_bounce_arena.tscn`
- Modify: `game/levels/bubble_bounce_arena.gd`
- Modify: `game/tests/integration/test_visual_target.gd`

**Interfaces:**
- Consumes: `BubbleBounceHud` (Task 2), `bounce_mode.score(peer_id)`, `bounce_mode.time_remaining()`, `_ammo` dict, `CompetitionArena.HOST_PEER_ID`/`GUEST_PEER_ID`.
- Produces: `@onready var _hud = $HUD/BubbleBounceHud`.

- [ ] **Step 1: Write the failing visual-contract test**

Add this method to `game/tests/integration/test_visual_target.gd`, and call it from `_run()` after `_test_boss_overlay_presence()`:

```gdscript
func _test_competition_hud_presence() -> bool:
	var cases := {
		"res://levels/bubble_bounce_arena.tscn": "BubbleBounceHud",
		"res://levels/star_race_arena.tscn": "StarRaceHud",
		"res://levels/treasure_dash_arena.tscn": "TreasureDashHud",
	}
	for level_path in cases:
		var hud_name: String = cases[level_path]
		var level = load(level_path).instantiate()
		root.add_child(level)
		await process_frame
		var hud = level.get_node_or_null("HUD/%s" % hud_name)
		if hud == null:
			level.queue_free()
			return _fail_bool("%s must compose %s" % [level_path.get_file(), hud_name])
		if not hud.has_method("render"):
			level.queue_free()
			return _fail_bool("%s must expose render()" % hud_name)
		level.queue_free()
	return true
```

Update `_run()`:

```gdscript
	if not await _test_boss_overlay_presence():
		return
	if not await _test_competition_hud_presence():
		return
	if not _test_complete_arena_composition():
		return
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `godot --headless --path game -s res://tests/integration/test_visual_target.gd`
Expected: FAIL with "bubble_bounce_arena.tscn must compose BubbleBounceHud".

- [ ] **Step 3: Add BubbleBounceHud to bubble_bounce_arena.tscn**

In `game/levels/bubble_bounce_arena.tscn`, add the ext_resource (existing ids go `1_arena` through `11_refill_visual`, so use `12_bubble_hud`):

```text
[ext_resource type="PackedScene" path="res://ui/bubble_bounce_hud.tscn" id="12_bubble_hud"]
```

Bump `load_steps` from 16 to 17.

Then add the HUD node inside the `HUD` CanvasLayer, after `TouchControls`:

```text
[node name="BubbleBounceHud" parent="HUD" instance=ExtResource("12_bubble_hud")]
```

- [ ] **Step 4: Wire the render call in bubble_bounce_arena.gd**

In `game/levels/bubble_bounce_arena.gd`, add an `@onready` reference and call `_hud.render(...)` at the end of `_step_level`. Add after the `@onready var projectiles_layer = $Projectiles` line:

```gdscript
@onready var _hud = $HUD/BubbleBounceHud
```

Then at the end of `_step_level`, after `_update_bubbles(delta)`:

```gdscript
	var local_peer_id := int(_local_hero().get_meta("peer_id", 0))
	_hud.render(
		bounce_mode.time_remaining(),
		bounce_mode.score(HOST_PEER_ID),
		bounce_mode.score(GUEST_PEER_ID),
		int(_ammo.get(local_peer_id, 0)),
	)
```

- [ ] **Step 5: Run the focused test to verify it passes**

Run: `godot --headless --path game -s res://tests/integration/test_visual_target.gd`
Expected: FAIL on "star_race_arena.tscn must compose StarRaceHud" (star_race wired in Task 8). The bubble_bounce assertion must pass.

Verify visually:

```bash
godot --path game -s res://tests/platform/live_inspect.gd --level=bubble_bounce
# ESC to quit; confirm the timer + per-player scores + ammo pips are visible.
```

- [ ] **Step 6: Commit**

```bash
git add game/levels/bubble_bounce_arena.tscn game/levels/bubble_bounce_arena.gd game/tests/integration/test_visual_target.gd
git commit -m "feat: wire bubble bounce competitive HUD"
```

---

### Task 8: Wire StarRaceHud into star_race_arena

**Files:**
- Modify: `game/levels/star_race_arena.tscn`
- Modify: `game/levels/star_race_arena.gd`
- Modify: `game/tests/integration/test_visual_target.gd` (no new method — `_test_competition_hud_presence` from Task 7 already covers star_race)

**Interfaces:**
- Consumes: `StarRaceHud` (Task 3), `race_mode.checkpoint_progress(peer_id)`, `race_mode` finish state (peer finished when `race_mode` reports it via `_finish_ticks` — use `race_mode._finish_ticks.has(peer_id)` is private; instead check `race_mode.has_passed_all_checkpoints(peer_id)` is not finish. Use the public `to_dict()` or track locally).
- Note: `StarRaceMode` exposes `_finish_ticks` as a private var. The cleanest public check is `race_mode._finish_ticks.has(peer_id)` — but that reads a private field. Instead, use the `peer_finished` signal already emitted by `StarRaceMode`. Wire the signal in `_setup_arena` to track finish state locally.

- [ ] **Step 1: Run the existing test to confirm it still fails on star_race**

Run: `godot --headless --path game -s res://tests/integration/test_visual_target.gd`
Expected: FAIL with "star_race_arena.tscn must compose StarRaceHud".

- [ ] **Step 2: Add StarRaceHud to star_race_arena.tscn**

In `game/levels/star_race_arena.tscn`, add the ext_resource (existing ids go `1_arena` through `12_checkpoint_visual`, so use `13_race_hud`):

```text
[ext_resource type="PackedScene" path="res://ui/star_race_hud.tscn" id="13_race_hud"]
```

Bump `load_steps` from 20 to 21.

Then add the HUD node inside the `HUD` CanvasLayer, after `TouchControls`:

```text
[node name="StarRaceHud" parent="HUD" instance=ExtResource("13_race_hud")]
```

- [ ] **Step 3: Wire the render call in star_race_arena.gd**

In `game/levels/star_race_arena.gd`, add an `@onready` reference, track finish state via the `peer_finished` signal, and call `_hud.render(...)` at the end of `_step_level`. The full updated file:

```gdscript
class_name StarRaceArena
extends CompetitionArena

## Friendly race: four ordered checkpoints per route, per-peer respawn at the
## most recent race checkpoint, and a grace period for the second finisher.

const StarRaceModeScript := preload("res://modes/star_race_mode.gd")

@onready var finish_line = $FinishLine
@onready var _hud = $HUD/StarRaceHud

var race_mode: RefCounted = null

var _host_tick: float = 0.0
var _peer_checkpoints: Dictionary = {}
var _peer_finished: Dictionary = {}


func _setup_arena() -> void:
	race_mode = StarRaceModeScript.new()
	race_mode.start()
	race_mode.race_completed.connect(_finish_match)
	race_mode.peer_finished.connect(_on_peer_finished)
	_peer_checkpoints[HOST_PEER_ID] = rabbit.global_position
	_peer_checkpoints[GUEST_PEER_ID] = fox.global_position
	finish_line.body_entered.connect(_on_finish_body_entered)
	for checkpoint in get_tree().get_nodes_in_group("race_checkpoint"):
		if checkpoint is Area2D:
			checkpoint.body_entered.connect(_on_checkpoint_body_entered.bind(checkpoint))


func _step_level(delta: float) -> void:
	_host_tick += delta
	race_mode.tick(delta, _host_tick)
	_hud.render(
		race_mode.checkpoint_progress(HOST_PEER_ID),
		race_mode.checkpoint_progress(GUEST_PEER_ID),
		_peer_finished.has(HOST_PEER_ID),
		_peer_finished.has(GUEST_PEER_ID),
	)


func _on_peer_finished(peer_id: int, _finish_tick: float) -> void:
	_peer_finished[peer_id] = true


func _on_checkpoint_body_entered(body: Node, checkpoint: Area2D) -> void:
	var peer_id := _peer_id_of(body)
	if peer_id == 0:
		return
	var checkpoint_id: String = checkpoint.get("checkpoint_id")
	if checkpoint_id.is_empty():
		return
	if race_mode.pass_checkpoint(peer_id, checkpoint_id, _host_tick):
		_peer_checkpoints[peer_id] = checkpoint.global_position


func _on_finish_body_entered(body: Node) -> void:
	var peer_id := _peer_id_of(body)
	if peer_id == 0:
		return
	race_mode.finish(peer_id, _host_tick)


func _respawn_fallen_hero(body: Node2D) -> void:
	var peer_id := _peer_id_of(body)
	if peer_id == 0:
		return
	body.respawn(_peer_checkpoints.get(peer_id, body.checkpoint_position))


func _peer_id_of(body: Node) -> int:
	if not body.has_method("respawn"):
		return 0
	return int(body.get_meta("peer_id", 0))
```

- [ ] **Step 4: Run the focused test to verify it passes**

Run: `godot --headless --path game -s res://tests/integration/test_visual_target.gd`
Expected: FAIL on "treasure_dash_arena.tscn must compose TreasureDashHud" (treasure_dash wired in Task 9). The star_race assertion must pass.

Verify visually:

```bash
godot --path game -s res://tests/platform/live_inspect.gd --level=star_race
# ESC to quit; confirm per-player checkpoint progress is visible.
```

- [ ] **Step 5: Commit**

```bash
git add game/levels/star_race_arena.tscn game/levels/star_race_arena.gd
git commit -m "feat: wire star race competitive HUD"
```

---

### Task 9: Wire TreasureDashHud into treasure_dash_arena

**Files:**
- Modify: `game/levels/treasure_dash_arena.tscn`
- Modify: `game/levels/treasure_dash_arena.gd`
- Modify: `game/tests/integration/test_visual_target.gd` (no new method — `_test_competition_hud_presence` from Task 7 already covers treasure_dash)

**Interfaces:**
- Consumes: `TreasureDashHud` (Task 4), `dash_mode.score(peer_id)`, `dash_mode.time_remaining()`, `CompetitionArena.HOST_PEER_ID`/`GUEST_PEER_ID`.

- [ ] **Step 1: Run the existing test to confirm it still fails on treasure_dash**

Run: `godot --headless --path game -s res://tests/integration/test_visual_target.gd`
Expected: FAIL with "treasure_dash_arena.tscn must compose TreasureDashHud".

- [ ] **Step 2: Add TreasureDashHud to treasure_dash_arena.tscn**

In `game/levels/treasure_dash_arena.tscn`, add the ext_resource (existing ids go `1_arena` through `9_hero_visual`, so use `10_treasure_hud`):

```text
[ext_resource type="PackedScene" path="res://ui/treasure_dash_hud.tscn" id="10_treasure_hud"]
```

Bump `load_steps` from 15 to 16.

Then add the HUD node inside the `HUD` CanvasLayer, after `TouchControls`:

```text
[node name="TreasureDashHud" parent="HUD" instance=ExtResource("10_treasure_hud")]
```

- [ ] **Step 3: Wire the render call in treasure_dash_arena.gd**

In `game/levels/treasure_dash_arena.gd`, add an `@onready` reference and call `_hud.render(...)` at the end of `_step_level`. Add after the `@onready var collectibles_layer = $Collectibles` line:

```gdscript
@onready var _hud = $HUD/TreasureDashHud
```

Then at the end of `_step_level`, after the spawn block:

```gdscript
	_hud.render(
		dash_mode.time_remaining(),
		dash_mode.score(HOST_PEER_ID),
		dash_mode.score(GUEST_PEER_ID),
	)
```

- [ ] **Step 4: Run the focused test to verify it passes**

Run: `godot --headless --path game -s res://tests/integration/test_visual_target.gd`
Expected: PASS (exit 0) — all assertions including all three competitive HUDs.

Verify visually:

```bash
godot --path game -s res://tests/platform/live_inspect.gd --level=treasure_dash
# ESC to quit; confirm the timer + per-player scores are visible.
```

- [ ] **Step 5: Commit**

```bash
git add game/levels/treasure_dash_arena.tscn game/levels/treasure_dash_arena.gd
git commit -m "feat: wire treasure dash competitive HUD"
```

---

### Task 10: Full Regression and Visual Baselines

**Files:**
- Run: `bash scripts/test_all.sh`
- Run: `DISPLAY=:0 python3 scripts/run_visual_tests.py`
- Create: new visual test baselines under `game/test-output/baselines/` (if the existing platform tests cover these levels; otherwise capture via `live_inspect.gd`).

- [ ] **Step 1: Run the full headless test gate**

Run: `bash scripts/test_all.sh`
Expected: PASS (exit 0) — all headless tests + existing visual tests + the new `test_boss_status_overlay.gd` and `test_competition_hud.gd` unit tests + the extended `test_visual_target.gd`.

- [ ] **Step 2: Run the deploy unit tests (unchanged, but confirm no regression)**

Run: `python3 -m unittest discover -s deploy/tests -t . -p 'test_*.py' -v`
Expected: PASS — deploy service is untouched but confirm nothing broke.

- [ ] **Step 3: Visually verify each level with live_inspect**

Run each level and confirm the HUD is visible and readable:

```bash
godot --path game -s res://tests/platform/live_inspect.gd --level=cloud_factory
godot --path game -s res://tests/platform/live_inspect.gd --level=crystal_caves
godot --path game -s res://tests/platform/live_inspect.gd --level=robot_boss
godot --path game -s res://tests/platform/live_inspect.gd --level=bubble_bounce
godot --path game -s res://tests/platform/live_inspect.gd --level=star_race
godot --path game -s res://tests/platform/live_inspect.gd --level=treasure_dash
```

For each: confirm the HUD renders (coop: score + hearts; boss: + phase/cycle/timer; competitive: timer/scores/progress as appropriate). ESC to quit each.

- [ ] **Step 4: Run the visual test platform (if DISPLAY available)**

Run: `DISPLAY=:0 python3 scripts/run_visual_tests.py`
Expected: all existing visual tests pass (3/3). The new HUDs don't add new platform tests in this cycle — they're verified via `live_inspect.gd` and the headless contract/unit tests.

- [ ] **Step 5: Final commit (if any baselines or docs changed)**

If `live_inspect.gd` captures or baselines were updated:

```bash
git add game/test-output/baselines/ docs/
git commit -m "feat: capture HUD visual baselines"
```

If nothing changed beyond the code, no commit needed — Tasks 1-9 already committed everything.

## Completion Gate

Complete only when:
1. `bash scripts/test_all.sh` passes (exit 0).
2. `test_boss_status_overlay.gd` and `test_competition_hud.gd` unit tests pass.
3. `test_visual_target.gd` extended assertions pass (coop HUD in cloud_factory/crystal_caves/robot_boss; boss overlay in robot_boss; three competitive HUDs in their arenas).
4. `live_inspect.gd` shows the HUD on every level.
5. No gameplay, physics, network, autoload, permission, or `project.godot` changes.
