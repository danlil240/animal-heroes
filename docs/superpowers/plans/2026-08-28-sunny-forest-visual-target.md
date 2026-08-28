# Sunny Forest Visual Target Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the geometric test-arena presentation with an original, polished Sunny Forest vertical slice without changing gameplay behavior.

**Architecture:** Existing gameplay nodes and collision remain authoritative. Original SVG assets are composed as visual-only children, typed GDScript components drive state-derived animation, and a shared palette/theme keeps the world and HUD coherent. The Compatibility renderer and bounded effects protect the SM-T220 performance target.

**Tech Stack:** Godot 4.x, typed GDScript, SVG assets, Tween/AnimationPlayer, Compatibility renderer, headless GDScript tests.

**Spec:** `docs/superpowers/specs/2026-08-28-sunny-forest-visual-target-design.md`

## Global Constraints

- Target viewport: 1340 by 800 landscape; also verify 1024 by 600.
- Target hardware: Samsung Galaxy Tab A7 Lite Wi-Fi SM-T220; minimum 30 FPS.
- All art must be original and may adopt only broad visual qualities from the reference.
- Existing physics, collision, profiles, checkpoints, input, cameras, and tests remain authoritative.
- Visual code may read gameplay state but must never mutate physics state or delay input.
- Avoid full-screen shaders, dynamic lights, blur, embedded raster data, and unbounded particles.
- Preserve the user's existing uncommitted change to `scripts/test_all.sh`.

## File Map

```text
game/art/characters/                 # Rabbit and fox SVG illustrations
game/art/collectibles/               # Star and checkpoint SVGs
game/art/effects/                    # Reusable bubble/action accent
game/art/environment/sunny_forest/   # Clouds, hills, foliage, platforms, accents
game/art/ui/                         # Jump and action SVG icons
game/theme/visual_palette.gd         # Named shared colors
game/theme/game_theme.tres           # Rounded HUD/button styles
game/visual/hero_visual.*            # State-derived hero presentation
game/visual/collectible_visual.*     # Reward bob/pop presentation
game/visual/checkpoint_visual.*      # Checkpoint presentation
game/visual/platform_visual.tscn     # Reusable platform presentation
game/visual/sunny_forest_background.* # Layered parallax background
game/tests/integration/test_visual_target.gd
docs/visual-target/                  # Screenshot and acceptance record
```

---

### Task 1: Palette, Theme, and Visual Contract

**Files:**
- Create: `game/theme/visual_palette.gd`
- Create: `game/theme/game_theme.tres`
- Create: `game/tests/integration/test_visual_target.gd`

**Interfaces:**
- Produces `VisualPalette` constants `SKY_TOP`, `SKY_BOTTOM`, `INK`, `GRASS_LIGHT`, `GRASS_DARK`, `ROCK_LIGHT`, `ROCK_DARK`, `STAR`, `CONTROL_BLUE`, and `CONTROL_BORDER`.
- Produces `res://theme/game_theme.tres` with normal, hover, and pressed `Button` styles.

- [ ] **Step 1: Write the failing contract test**

Create `test_visual_target.gd` with the existing async SceneTree-test pattern:

```gdscript
extends SceneTree

const REQUIRED_COLORS := [
	"SKY_TOP", "SKY_BOTTOM", "INK", "GRASS_LIGHT", "GRASS_DARK",
	"ROCK_LIGHT", "ROCK_DARK", "STAR", "CONTROL_BLUE", "CONTROL_BORDER",
]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var palette := load("res://theme/visual_palette.gd")
	var theme := load("res://theme/game_theme.tres")
	if palette == null or theme == null:
		_fail("visual palette and game theme must load")
		return
	var constants: Dictionary = palette.get_script_constant_map()
	for color_name in REQUIRED_COLORS:
		if not constants.has(color_name):
			_fail("missing palette color %s" % color_name)
			return
	if not theme.has_stylebox("normal", "Button"):
		_fail("game theme must style buttons")
		return
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
```

- [ ] **Step 2: Run it and verify failure**

Run: `godot --headless --path game -s res://tests/integration/test_visual_target.gd`

Expected: FAIL with `visual palette and game theme must load`.

- [ ] **Step 3: Add the palette and theme**

Implement:

```gdscript
class_name VisualPalette
extends RefCounted

const SKY_TOP := Color("168af2")
const SKY_BOTTOM := Color("5ed6f2")
const INK := Color("17294a")
const GRASS_LIGHT := Color("8de047")
const GRASS_DARK := Color("239447")
const ROCK_LIGHT := Color("bf7b32")
const ROCK_DARK := Color("704424")
const STAR := Color("ffd33d")
const CONTROL_BLUE := Color(0.08, 0.49, 0.90, 0.76)
const CONTROL_BORDER := Color(0.86, 0.97, 1.0, 0.95)
```

Build `game_theme.tres` with 28-pixel corner radii, a four-pixel pale border, white 28-pixel text, and a six-pixel dark-blue shadow. Pressed state darkens the fill and reduces the shadow to two pixels.

- [ ] **Step 4: Run focused and full tests**

Run the focused visual test, then `bash scripts/test_all.sh`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add game/theme game/tests/integration/test_visual_target.gd
git commit -m "feat: add sunny forest visual foundation"
```

---

### Task 2: Layered Sunny Forest Background

**Files:**
- Create: `game/art/environment/sunny_forest/cloud.svg`
- Create: `game/art/environment/sunny_forest/distant_hills.svg`
- Create: `game/art/environment/sunny_forest/foliage_cluster.svg`
- Create: `game/art/environment/sunny_forest/flower_cluster.svg`
- Create: `game/art/environment/sunny_forest/mushroom.svg`
- Create: `game/visual/sunny_forest_background.gd`
- Create: `game/visual/sunny_forest_background.tscn`
- Modify: `game/tests/integration/test_visual_target.gd`

**Interfaces:**
- Produces `SunnyForestBackground.set_focus_x(world_x: float) -> void`.
- Produces scene children `Sky`, `Far`, `Mid`, and `Frame`.

- [ ] **Step 1: Add a failing background contract**

Load and instantiate `sunny_forest_background.tscn`, assert all four named layers exist, call `set_focus_x(400.0)`, and assert `Far.position.x != Mid.position.x`.

- [ ] **Step 2: Run the test**

Expected: FAIL because the background scene is absent.

- [ ] **Step 3: Author original SVG scenery**

Use explicit viewBoxes and no filters/fonts/embedded images:

- `cloud.svg`: 360×150, rounded white lobes and pale-blue underside.
- `distant_hills.svg`: 1600×420, four overlapping cool blue/teal rounded silhouettes.
- `foliage_cluster.svg`: 420×280, seven lime/emerald leaf masses, maximum 24 paths.
- `flower_cluster.svg`: 220×160, three coral/yellow/white flowers.
- `mushroom.svg`: 230×250, red rounded cap, five cream spots, cream stem.

- [ ] **Step 4: Implement background behavior**

```gdscript
class_name SunnyForestBackground
extends Node2D

const FAR_RATIO := 0.08
const MID_RATIO := 0.18

func set_focus_x(world_x: float) -> void:
	$Far.position.x = -world_x * FAR_RATIO
	$Mid.position.x = -world_x * MID_RATIO
```

Compose the scene with z-indexes -40/-30/-20/20. Keep `Frame` decoration outside the central traversal band y=430..720.

- [ ] **Step 5: Run tests and commit**

Run focused and full tests. Commit as `feat: add layered sunny forest scenery`.

---

### Task 3: Grass-Topped Platform Presentation

**Files:**
- Create: `game/art/environment/sunny_forest/platform_ground.svg`
- Create: `game/art/environment/sunny_forest/platform_small.svg`
- Create: `game/visual/platform_visual.tscn`
- Modify: `game/levels/test_arena.tscn`
- Modify: `game/tests/integration/test_visual_target.gd`

**Interfaces:**
- Consumes the existing `Ground`, `PlatformA`, `PlatformB`, and `PlatformC` collision nodes without changing transforms or shapes.
- Produces a `Visual` child for each gameplay surface.

- [ ] **Step 1: Add a failing separation test**

For every surface, assert `CollisionShape2D` and `Visual` exist and placeholder nodes `GroundArt`/`Art` do not.

- [ ] **Step 2: Run and verify failure**

Expected: FAIL because `Ground/Visual` is absent.

- [ ] **Step 3: Create original platform SVGs**

`platform_ground.svg` is 1600×150 with a bright grass fringe, warm faceted rock face, and dark underside. `platform_small.svg` is 240×115 with a rounded grass cap and tapered rock underside. Keep the playable top visually flat and never place art more than 15 pixels above its collider edge.

- [ ] **Step 4: Compose visuals**

Replace placeholder polygons with instantiated `Visual` scenes. Scale only the art child to collider width; never scale or move collision nodes.

- [ ] **Step 5: Verify and commit**

Run visual, arena, and full tests. Commit as `feat: illustrate sunny forest platforms`.

---

### Task 4: Friendly Stars and Checkpoint

**Files:**
- Create: `game/art/collectibles/star_friend.svg`
- Create: `game/art/collectibles/checkpoint_flower.svg`
- Create: `game/visual/collectible_visual.gd` and `.tscn`
- Create: `game/visual/checkpoint_visual.gd` and `.tscn`
- Modify: `game/levels/test_arena.gd`
- Modify: `game/levels/test_arena.tscn`
- Modify: `game/tests/integration/test_visual_target.gd`

**Interfaces:**
- Produces `CollectibleVisual.set_phase_offset(value: float) -> void` and `play_collected() -> void`.
- Produces `CheckpointVisual.set_active(active: bool) -> void`.
- Preserves exactly ten nodes in `arena_collectible`.

- [ ] **Step 1: Add failing reward contracts**

Assert both visual scenes load, each arena collectible owns `Visual`, the count remains ten, and `Checkpoint/Visual` exists.

- [ ] **Step 2: Run and verify failure**

Expected: FAIL because reward scenes do not exist.

- [ ] **Step 3: Author original assets**

`star_friend.svg` is 96×96: rounded gold star, orange rim, two oval eyes, small highlight, dark outline. `checkpoint_flower.svg` is 180×220: leafy stem, cyan flower/flag form, yellow center, warm stone base.

- [ ] **Step 4: Implement bounded animation**

Star idle motion is a phase-shifted sine bob capped at five pixels and rotation capped at 0.06 radians. `play_collected()` stops idle processing and tweens scale to 1.35 and alpha to zero over 0.16 seconds without spawning nodes. Checkpoint activation tweens to scale 1.08 and a brighter modulation over 0.18 seconds.

- [ ] **Step 5: Integrate activation**

Keep every star's existing position/group. At the end of `_activate_checkpoint`:

```gdscript
	var visual := $Checkpoint.get_node_or_null("Visual")
	if visual != null and visual.has_method("set_active"):
		visual.set_active(true)
```

- [ ] **Step 6: Verify and commit**

Run visual, arena, and full tests. Commit as `feat: add friendly forest rewards`.

---

### Task 5: Expressive Rabbit and Fox Visuals

**Files:**
- Create: `game/art/characters/riki_rabbit.svg`
- Create: `game/art/characters/foxy_fox.svg`
- Create: `game/art/effects/bubble_ring.svg`
- Create: `game/visual/hero_visual.gd` and `.tscn`
- Modify: `game/player/player_body.gd`
- Modify: `game/levels/test_arena.tscn`
- Modify: `game/tests/integration/test_player_scene.gd`
- Modify: `game/tests/integration/test_visual_target.gd`

**Interfaces:**
- Produces `PlayerBody.facing_direction: float`, always -1 or 1.
- Produces `HeroVisual.configure(kind: String, body: CharacterBody2D) -> void`.
- HeroVisual reads body velocity, floor state, and facing; it never writes to the body.

- [ ] **Step 1: Add failing facing tests**

After positive and negative input, assert `facing_direction` is 1 and -1 respectively.

- [ ] **Step 2: Run and verify failure**

Expected: failure because `facing_direction` does not exist.

- [ ] **Step 3: Implement facing state**

Add `var facing_direction: float = 1.0`. In `apply_input`, update it only when `absf(_input_axis) > 0.01`.

- [ ] **Step 4: Author original heroes**

`riki_rabbit.svg` is 150×190: white rabbit, large pink-lined ears, expressive eyes, rounded smiling muzzle, red top, blue shorts, pale shoes, dark outline. `foxy_fox.svg` is 175×180: orange fox, cream muzzle/chest/ears/tail tip, large tail, green top, dark shorts, pale shoes, dark outline. Use standing action-ready poses, not poses copied from the reference. `bubble_ring.svg` is 96×96: a transparent cyan ring with two white highlights and a dark-blue lower rim; no filter or embedded raster data.

- [ ] **Step 5: Implement state-derived animation**

Flip art from `facing_direction`. Idle uses a two-pixel breathing bob. Running uses a five-pixel bob and rotation capped at 0.05 radians. Ascent targets scale (0.94, 1.08); descent targets (1.05, 0.95). When `body.snapshot().action_pressed` changes from false to true, briefly show the preallocated bubble ring and tween a forward hand/whole-body gesture for 0.16 seconds. Track the prior heart count and global position: a heart decrease triggers a restrained 0.18-second recoil, while a teleport to the checkpoint triggers a cheerful 0.22-second recovery scale. Smooth ordinary pose values with `1.0 - exp(-12.0 * delta)`. Never spawn an effect node or assign to the body.

- [ ] **Step 6: Replace placeholder hero polygons**

Replace `BodyArt` with `Visual` while preserving collision, cameras, profiles, node names, and spawn positions.

- [ ] **Step 7: Test separation and commit**

Call visual processing and assert body position/velocity do not change. Run player, arena, visual, and full tests. Commit as `feat: illustrate and animate animal heroes`.

---

### Task 6: Illustrated Controls and Partner Indicator

**Files:**
- Create: `game/art/ui/action_bubble.svg`
- Create: `game/art/ui/jump_wing.svg`
- Modify: `game/ui/touch_controls.tscn`
- Modify: `game/levels/test_arena.tscn`
- Modify: `game/tests/integration/test_hebrew_ui.gd`
- Modify: `game/tests/integration/test_visual_target.gd`

**Interfaces:**
- Preserves paths `Movement/Left`, `Movement/Right`, `Jump`, `Action`, and `HUD/PartnerIndicator/Arrow`.
- Preserves `TouchControls.input_frame()` and 128×128 targets.

- [ ] **Step 1: Add failing UI tests**

Assert the controls use `game_theme.tres`, Jump/Action have icons, all four targets remain at least 128×128, and the indicator has an `Outline` sibling.

- [ ] **Step 2: Run and verify failure**

Expected: FAIL because theme/icons/outline are absent.

- [ ] **Step 3: Author icons**

`jump_wing.svg` is 72×72 with a white upward wing/boot symbol and dark outline. `action_bubble.svg` is 72×72 with a cyan bubble, white highlights, and dark outline.

- [ ] **Step 4: Apply visual styling**

Assign the shared theme without changing anchors or dimensions. Keep arrow glyphs for direction; assign icons to Jump/Action and use 20-pixel Hebrew labels. Add a slightly larger dark-blue `Outline` polygon behind the gold partner arrow.

- [ ] **Step 5: Verify and commit**

Run Hebrew UI, arena, visual, and full tests, including simultaneous touch behavior. Commit as `feat: style child-friendly game controls`.

---

### Task 7: Final Composition and Acceptance

**Files:**
- Modify: `game/levels/test_arena.gd`
- Modify: `game/levels/test_arena.tscn`
- Modify: `game/tests/integration/test_visual_target.gd`
- Create: `docs/visual-target/sunny-forest-acceptance.md`
- Create during verification: `docs/visual-target/sunny-forest-1340x800.png`

**Interfaces:**
- Produces the complete runnable visual target.
- Consumes all scenes and assets from Tasks 1–6.

- [ ] **Step 1: Add the final composition test**

Assert the background exists at negative z-index, all gameplay contracts remain intact, exactly ten collectibles exist, placeholder polygons are absent, and touch targets pass at 1340×800 and 1024×600.

- [ ] **Step 2: Finish composition**

Instantiate `SunnyForestBackground` and in arena `_process` call `set_focus_x(_local_hero().global_position.x)`. Adjust only visual offsets, z-indexes, scales, and colors; never gameplay geometry.

- [ ] **Step 3: Run all automated verification**

```bash
godot --headless --path game -s res://tests/integration/test_visual_target.gd
godot --headless --path game -s res://tests/integration/test_local_arena.gd
godot --headless --path game -s res://tests/integration/test_player_scene.gd
godot --headless --path game -s res://tests/integration/test_hebrew_ui.gd
bash scripts/test_all.sh
```

Expected: every command exits zero.

- [ ] **Step 4: Render and inspect**

Capture `sunny-forest-1340x800.png` showing both heroes, stars, grass-topped platforms, layered scenery, checkpoint, and all controls. Inspect at full and 50% size.

- [ ] **Step 5: Record acceptance**

In `sunny-forest-acceptance.md` record PASS/FAIL for original art, hero distinction, traversal readability, layered depth, reward/checkpoint visibility, control readability, lack of occlusion, and restrained effects. Fix and rerender until all non-device rows pass.

- [ ] **Step 6: Validate target devices**

Run for five minutes on both SM-T220 tablets with both heroes moving/jumping. Record average/minimum FPS and touch/thermal issues. Minimum is 30 FPS. If devices are unavailable, mark only these rows `PENDING DEVICE CHECK` and do not claim final device performance.

- [ ] **Step 7: Final regression and commit**

Run `bash scripts/test_all.sh`. Expected: PASS. Commit as `feat: establish sunny forest visual target`.

## Completion Gate

Complete only when automated tests pass, screenshot QA passes, gameplay behavior is unchanged, and device performance is either measured at 30 FPS or higher on both tablets or explicitly recorded as the sole pending acceptance item.
