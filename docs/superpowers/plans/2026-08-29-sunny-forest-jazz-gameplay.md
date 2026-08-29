# Sunny Forest Momentum, Combat, and Secrets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Turn Sunny Forest into a polished three-to-five-minute action-platforming vertical slice with momentum movement, held-fire bubble combat, a shared combo, branching routes, springs, and three optional secrets.

**Architecture:** Keep the current TwoPlayerLevel/CoopLevel ownership and host-authoritative world-event path. Add focused rules to existing player, projectile, enemy, score, HUD, and Sunny Forest owners; introduce only SpringPad, SecretTrigger, BreakableBramble, CameraFeedback, and a small TeamCombo value object. Re-author only Sunny Forest and preserve the four-button touch layout.

**Tech Stack:** Godot 4.7.2, typed GDScript, Godot scenes/resources, original SVG/WAV assets, existing headless/platform test harnesses, Bash, and Python stdlib.

**Spec:** docs/superpowers/specs/2026-08-29-sunny-forest-jazz-gameplay-design.md

## Global Constraints

- Keep package id org.danlil.animalheroes unchanged.
- Add no third-party dependencies and no copyrighted Jazz Jackrabbit expression.
- Preserve left/right/jump/action controls and touch targets of at least 96 px.
- Keep physics at 30 Hz and never tune physics/network ticks to hide rendering cost.
- Preserve host authority and reconnect replay protection.
- Keep budgets at enemy <= 12, projectile <= 24, and particle <= 80.
- Keep the exact four Android permissions unchanged.
- Do not redesign later campaign levels or competitive modes.
- Never stage or delete existing operator evidence in docs/test-results or generated game/test-output.
- Run targeted tests after each red/green cycle and the canonical gates before completion.

## File Map

**New focused units**

- game/core/team_combo.gd — bounded team combo and reconnect state.
- game/world/spring_pad.gd and spring_pad.tscn — launch behavior and presentation.
- game/world/secret_trigger.gd and secret_trigger.tscn — one idempotent secret.
- game/world/breakable_bramble.gd and breakable_bramble.tscn — projectile-opened secret barrier.
- game/visual/camera_feedback.gd — local look-ahead and bounded shake.
- game/art/objects/spring_pad.svg, golden_carrot.svg, cracked_bramble.svg — original art.
- game/art/effects/speed_streak.svg — original speed feedback.
- game/tests/unit/test_momentum_movement.gd
- game/tests/unit/test_team_combo.gd
- game/tests/unit/test_spring_and_secrets.gd
- game/tests/integration/test_sunny_forest_action_combat.gd
- game/tests/integration/test_sunny_forest_reconnect_rich_state.gd
- game/tests/platform/test_sunny_forest_momentum_combat.gd

**Existing owners changed**

- Player profile/body/state: movement tuning and state.
- Bubble inventory/projectile: unlimited basic shot plus ten spread charges.
- Enemy actor/scenes/visuals: health, recoil, hurt cooldown, and defeat feedback.
- Team score, CoopLevel, SunnyForest: combo scoring and authoritative events.
- Gameplay HUD, hero visuals, AudioDirector: readable feedback.
- Sunny Forest scene and its current tests: five-section route re-authoring.
- Build metadata: application protocol version 2.
- Device/performance and release checklist: automated and human gates.

---

### Task 1: Momentum Movement Contract

**Files:**
- Create: game/tests/unit/test_momentum_movement.gd
- Modify: game/player/player_profile.gd
- Modify: game/player/player_body.gd
- Modify: game/player/player_state.gd
- Modify: game/player/rabbit_profile.tres
- Modify: game/player/fox_profile.tres
- Modify: game/tests/unit/test_player_rules.gd
- Modify: game/world/enemy_actor.gd

**Interfaces:**
- Consumes: PlayerInput.InputFrame and PlayerBody.physics_step(delta).
- Produces: profile fields max_run_speed, ground_acceleration, ground_deceleration, air_acceleration, jump_cut_gravity_multiplier; PlayerBody.apply_stomp_rebound(); snapshot fields run_speed_ratio and just_landed.

- [ ] **Step 1: Write the failing fixed-step movement test**

Create a SceneTree test with floor collision and 30 Hz stepping. Include these assertions:

~~~gdscript
var body = load("res://player/player_body.gd").new()
body.profile = load("res://player/rabbit_profile.tres")
root.add_child(body)
var right = load("res://player/player_input.gd").InputFrame.new()
right.axis = 1.0
body.apply_input(right)
for tick in 11:
	body.physics_step(1.0 / 30.0)
if body.velocity.x < body.profile.max_run_speed * 0.9:
	_fail("rabbit must reach 90 percent run speed within 0.35 seconds")
	return
var release_x := body.position.x
body.apply_input(load("res://player/player_input.gd").InputFrame.new())
for tick in 30:
	body.physics_step(1.0 / 30.0)
	if absf(body.velocity.x) < 0.01:
		break
if body.position.x - release_x > 80.0:
	_fail("release stopping distance must stay within 80 pixels")
	return
body.velocity.y = 100.0
body.apply_stomp_rebound()
if body.velocity.y >= -300.0:
	_fail("stomp rebound must launch upward")
	return
~~~

Add fixed-step helpers that compare a held jump with a one-tick tap and require held height >= 1.25 times tapped height. Assert reversal brakes before accelerating and air acceleration is lower than ground acceleration.

- [ ] **Step 2: Run the new test in red state**

Run:

~~~bash
godot --headless --path game -s res://tests/unit/test_momentum_movement.gd
~~~

Expected: FAIL because max_run_speed and apply_stomp_rebound do not exist.

- [ ] **Step 3: Implement the minimal model**

Add typed exports:

~~~gdscript
@export var max_run_speed: float = 340.0
@export var ground_acceleration: float = 1400.0
@export var ground_deceleration: float = 1800.0
@export var air_acceleration: float = 850.0
@export var jump_cut_gravity_multiplier: float = 2.4
~~~

Set Riki to 360/1500/1900/900/2.4 and Foxy to 340/1400/1800/850/2.4. Retain existing jump speeds, health, and heavy-push distinction. Replace instant horizontal assignment with:

~~~gdscript
var acceleration := profile.ground_acceleration if was_on_floor else profile.air_acceleration
var target_speed := _input_axis * profile.max_run_speed
if is_zero_approx(_input_axis):
	velocity.x = move_toward(velocity.x, 0.0, profile.ground_deceleration * step)
else:
	velocity.x = move_toward(velocity.x, target_speed, acceleration * step)
if not _jump_pressed and velocity.y < 0.0:
	velocity.y += gravity * (profile.jump_cut_gravity_multiplier - 1.0) * step
~~~

Add STOMP_REBOUND_SPEED = 340.0 and apply_stomp_rebound(). EnemyActor calls it after a stomp. Snapshot run_speed_ratio is abs(velocity.x)/max_run_speed; just_landed is true for exactly one air-to-floor physics step.

- [ ] **Step 4: Run movement regressions**

~~~bash
godot --headless --path game -s res://tests/unit/test_momentum_movement.gd
godot --headless --path game -s res://tests/unit/test_player_rules.gd
godot --headless --path game -s res://tests/integration/test_player_scene.gd
~~~

Expected: all commands exit 0.

- [ ] **Step 5: Commit**

~~~bash
git add game/player game/world/enemy_actor.gd game/tests/unit/test_momentum_movement.gd game/tests/unit/test_player_rules.gd
git commit -m "feat: add momentum platforming movement"
~~~

---

### Task 2: Springs, Look-ahead, and Speed Presentation

**Files:**
- Create: game/world/spring_pad.gd
- Create: game/world/spring_pad.tscn
- Create: game/visual/camera_feedback.gd
- Create: game/art/objects/spring_pad.svg
- Create: game/art/effects/speed_streak.svg
- Create: game/tests/unit/test_spring_and_secrets.gd
- Modify: game/levels/two_player_level.gd
- Modify: game/visual/hero_visual.gd
- Modify: game/visual/hero_visual.tscn

**Interfaces:**
- Consumes: PlayerBody.velocity, run_speed_ratio, just_landed, and local Camera2D.
- Produces: SpringPad.try_launch(body) -> bool, launched(peer_id), CameraFeedback.add_impulse(amount).

- [ ] **Step 1: Write the failing spring test**

~~~gdscript
var spring = load("res://world/spring_pad.gd").new()
spring.launch_velocity = Vector2(120.0, -720.0)
var hero = load("res://player/player_body.gd").new()
hero.peer_id = 1
root.add_child(hero)
if not spring.try_launch(hero):
	_fail("spring must accept a live player")
	return
if hero.velocity != Vector2(120.0, -720.0):
	_fail("spring must apply exact launch velocity")
	return
if spring.try_launch(hero):
	_fail("spring cooldown must reject an immediate duplicate")
	return
~~~

- [ ] **Step 2: Run it in red state**

~~~bash
godot --headless --path game -s res://tests/unit/test_spring_and_secrets.gd
~~~

Expected: FAIL because spring_pad.gd does not exist.

- [ ] **Step 3: Implement spring and local feedback**

Implement SpringPad as Area2D with exported launch_velocity, 0.25 second per-peer cooldown, body_entered connection, host_step(delta), and launched signal. Only peer ids 1 or 2 are accepted. Add an original leaf-and-coil SVG and local compress/extend animation.

CameraFeedback follows the current local hero:

~~~gdscript
var target_x := clampf(hero.velocity.x * 0.22, -90.0, 90.0)
position.x = lerpf(position.x, target_x, 1.0 - exp(-8.0 * delta))
_impulse = _impulse.lerp(Vector2.ZERO, 1.0 - exp(-18.0 * delta))
position += _impulse
~~~

Clamp add_impulse to 10 px. Attach feedback from TwoPlayerLevel without changing camera ownership. HeroVisual shows the speed streak above 0.85 run ratio and triggers one landing squash when just_landed becomes true.

- [ ] **Step 4: Run focused regressions**

~~~bash
godot --headless --path game -s res://tests/unit/test_spring_and_secrets.gd
godot --headless --path game -s res://tests/unit/test_momentum_movement.gd
godot --headless --path game -s res://tests/integration/test_player_scene.gd
~~~

Expected: all commands exit 0.

- [ ] **Step 5: Commit**

~~~bash
git add game/world/spring_pad.gd game/world/spring_pad.tscn game/visual/camera_feedback.gd game/visual/hero_visual.gd game/visual/hero_visual.tscn game/art/objects/spring_pad.svg game/art/effects/speed_streak.svg game/levels/two_player_level.gd game/tests/unit/test_spring_and_secrets.gd
git commit -m "feat: add spring traversal feedback"
~~~

---

### Task 3: Basic and Powered Bubble Fire

**Files:**
- Modify: game/player/bubble_inventory.gd
- Modify: game/world/bubble_projectile.gd
- Modify: game/world/bubble_projectile.tscn
- Modify: game/tests/unit/test_world_rules.gd

**Interfaces:**
- Consumes: ObjectPool acquire/release and projectile host_step.
- Produces: BubbleInventory.grant_spread(peer_id, amount := 10), consume_spread(peer_id), kind(peer_id), snapshot/restore; BubbleProjectile.launch(owner_id, origin, shot_velocity, sequence, kind, fan_index).

- [ ] **Step 1: Replace old five-ammo tests with failing powered-fire tests**

~~~gdscript
var inventory = load("res://player/bubble_inventory.gd").new()
if inventory.kind(1) != "basic" or inventory.remaining(1) != 0:
	_fail("heroes must start with unlimited basic fire")
	return
if inventory.grant_spread(1) != 10 or inventory.kind(1) != "spread":
	_fail("bubble flower must grant ten spread shots")
	return
var bubble = load("res://world/bubble_projectile.tscn").instantiate()
root.add_child(bubble)
if not bubble.launch(1, Vector2.ZERO, Vector2(360.0, -40.0), 1, "spread", -1):
	_fail("spread member must launch")
	return
if bubble.projectile_kind != "spread" or bubble.fan_index != -1:
	_fail("spread identity must persist")
	return
~~~

Also assert restore rejects unknown kinds, peers outside 1/2, counts above ten, and duplicate malformed entries.

- [ ] **Step 2: Run in red state**

~~~bash
godot --headless --path game -s res://tests/unit/test_world_rules.gd
~~~

Expected: FAIL on missing APIs.

- [ ] **Step 3: Implement the bounded weapon model**

Use BASIC = basic, SPREAD = spread, MAX_POWERED_SHOTS = 10. Store only powered entries. kind() returns basic at zero. Snapshot deep-copies entries shaped as {kind, remaining}; restore validates all values before replacing state.

Use this projectile signature and validation:

~~~gdscript
func launch(owner_id: int, origin: Vector2, shot_velocity: Vector2, sequence: int, kind: String = "basic", member_index: int = 0) -> bool:
	if owner_id not in [1, 2] or sequence <= 0 or shot_velocity.length_squared() < 1.0:
		return false
	if kind not in ["basic", "spread"] or member_index < -1 or member_index > 1:
		return false
	owner_peer_id = owner_id
	projectile_id = "bubble-%d-%d" % [sequence, member_index]
	projectile_kind = kind
	fan_index = member_index
	position = origin
	velocity = shot_velocity
	_remaining = LIFETIME
	active = true
	visible = true
	monitoring = true
	monitorable = true
	return true
~~~

Reset and restore projectile kind/fan identity. Tint and scale spread shots without a second scene.

- [ ] **Step 4: Run tests and import**

~~~bash
godot --headless --path game -s res://tests/unit/test_world_rules.gd
godot --headless --editor --path game --quit
~~~

Expected: both commands exit 0.

- [ ] **Step 5: Commit**

~~~bash
git add game/player/bubble_inventory.gd game/world/bubble_projectile.gd game/world/bubble_projectile.tscn game/tests/unit/test_world_rules.gd
git commit -m "feat: add basic and spread bubble shots"
~~~

---

### Task 4: Durable Enemies and Hit Feedback

**Files:**
- Modify: game/world/enemy_actor.gd
- Modify: game/world/beetle_enemy.tscn
- Modify: game/world/seed_enemy.tscn
- Modify: game/visual/enemy_visual.gd
- Modify: game/visual/seed_enemy_visual.gd
- Modify: game/audio/audio_director.gd
- Modify: game/tests/unit/test_world_rules.gd
- Modify: game/tests/integration/test_sunny_forest.gd

**Interfaces:**
- Consumes: BubbleProjectile.try_enemy_hit, PlayerBody.apply_stomp_rebound.
- Produces: health, max_health, hurt_remaining, try_bubble(peer_id, impulse), hurt(enemy_id, peer_id), snapshot_state().

- [ ] **Step 1: Write failing durability tests**

~~~gdscript
var beetle = load("res://world/beetle_enemy.tscn").instantiate()
beetle.enemy_id = "durable-beetle"
root.add_child(beetle)
var defeats := 0
beetle.defeated.connect(func(_id: String, _peer: int) -> void: defeats += 1)
if not beetle.try_bubble(1, Vector2(120.0, -40.0)):
	_fail("first beetle hit must be accepted")
	return
if beetle.health != 1 or beetle.motion_state == beetle.DEFEATED:
	_fail("first beetle hit must not defeat")
	return
if beetle.try_bubble(1, Vector2.ZERO):
	_fail("hurt cooldown must reject simultaneous hit")
	return
beetle.host_step(beetle.HURT_COOLDOWN + 0.01)
if not beetle.try_bubble(1, Vector2.ZERO) or defeats != 1:
	_fail("second separated hit must defeat once")
	return
~~~

Add a seed assertion proving one accepted hit defeats.

- [ ] **Step 2: Run in red state**

~~~bash
godot --headless --path game -s res://tests/unit/test_world_rules.gd
~~~

Expected: FAIL because health and hurt cooldown are absent.

- [ ] **Step 3: Implement health, recoil, and visual state**

Add HURT state, HURT_COOLDOWN = 0.16, exported max_health = 2, health, hurt_remaining, and prior motion state. Seed scenes set max_health = 1. Accepted hits decrement once, clamp recoil to 180 px/s, emit hurt when alive, and use the existing one-time defeat path at zero. HURT host stepping applies recoil and returns to prior state after cooldown.

snapshot_state returns id, kind, motion state, health, hurt remaining, position, velocity, and direction. restore_state validates all fields before mutation. Visuals use motion plus scale/white flash, not color alone. Add cue names shot, enemy_hit, enemy_defeat, spring, combo, and secret while retaining 12 total voices and four projectile voices.

- [ ] **Step 4: Run combat regressions**

~~~bash
godot --headless --path game -s res://tests/unit/test_world_rules.gd
godot --headless --path game -s res://tests/integration/test_sunny_forest.gd
~~~

Expected: both commands exit 0 after old one-hit expectations are revised.

- [ ] **Step 5: Commit**

~~~bash
git add game/world/enemy_actor.gd game/world/beetle_enemy.tscn game/world/seed_enemy.tscn game/visual/enemy_visual.gd game/visual/seed_enemy_visual.gd game/audio/audio_director.gd game/tests/unit/test_world_rules.gd game/tests/integration/test_sunny_forest.gd
git commit -m "feat: add readable multi-hit combat"
~~~

---

### Task 5: Host Held Fire and Shared Combo

**Files:**
- Create: game/core/team_combo.gd
- Create: game/tests/unit/test_team_combo.gd
- Create: game/tests/integration/test_sunny_forest_action_combat.gd
- Modify: game/core/team_score.gd
- Modify: game/levels/two_player_level.gd
- Modify: game/levels/coop_level.gd
- Modify: game/levels/sunny_forest.gd

**Interfaces:**
- Consumes: held action state, ActionResolver, weapon/projectile APIs, enemy events.
- Produces: TwoPlayerLevel.publish_world_event(kind, payload), TeamCombo preview/commit/refresh/step/snapshot/restore, five-shots-per-second authority cadence.

- [ ] **Step 1: Write failing combo and action-priority tests**

~~~gdscript
var combo = load("res://core/team_combo.gd").new()
if combo.preview_multiplier() != 1:
	_fail("first event must score at 1x")
	return
combo.commit_scored_event()
if combo.preview_multiplier() != 2:
	_fail("second chained event must score at 2x")
	return
combo.commit_scored_event()
combo.commit_scored_event()
combo.commit_scored_event()
if combo.multiplier != 4:
	_fail("combo must cap at 4x")
	return
combo.step(2.51)
if combo.multiplier != 1 or combo.remaining != 0.0:
	_fail("combo must expire after 2.5 seconds")
	return
~~~

The integration test holds action for one second away from interactables and requires exactly five shot sequences. It presses action at FallenLog and requires one interaction, zero shots until release, then immediate fire after moving away. Spread mode must create exactly three fan members per accepted sequence while consuming one charge.

- [ ] **Step 2: Run both in red state**

~~~bash
godot --headless --path game -s res://tests/unit/test_team_combo.gd
godot --headless --path game -s res://tests/integration/test_sunny_forest_action_combat.gd
~~~

Expected: both fail on missing behavior.

- [ ] **Step 3: Implement publication, cadence, and combo**

Extract sequence/RPC publication:

~~~gdscript
func publish_world_event(kind: String, payload: Dictionary) -> bool:
	if not _is_world_authority() or kind.is_empty():
		return false
	_next_world_event_sequence += 1
	if not apply_world_event(_next_world_event_sequence, kind, payload):
		return false
	if _has_live_world_peer():
		_receive_world_event.rpc(_next_world_event_sequence, kind, payload)
	return true
~~~

Sunny Forest tracks per-peer fire cooldown, previous action, and interaction claim. The authority inspects both heroes. A rising action near an interactable claims the press until release. Otherwise fire immediately and every 0.20 seconds. Basic velocity is (direction*360, 0). Spread velocities are (direction*360, -70/0/70). Acquire all three objects before consuming one spread charge; if the pool cannot supply all three, release acquired members, preserve the charge, and emit one bounded debug diagnostic. Respawn, disconnect, and input reset clear held-fire timing and interaction claims without clearing powered charges.

TeamCombo uses WINDOW=2.5 and MAX_MULTIPLIER=4. preview_multiplier returns 1 when inactive and min(multiplier+1, 4) while active. commit_scored_event assigns the preview and resets the window. refresh resets only an active window. Extend TeamScore.award(event_id, category, multiplier := 1), clamped 1–4, and add secret value 100. Preview, award, and only then commit when points are nonzero. Teamwork always awards at 1x and refreshes an active combo.

- [ ] **Step 4: Run focused regressions**

~~~bash
godot --headless --path game -s res://tests/unit/test_team_combo.gd
godot --headless --path game -s res://tests/unit/test_world_rules.gd
godot --headless --path game -s res://tests/integration/test_sunny_forest_action_combat.gd
godot --headless --path game -s res://tests/integration/test_sunny_forest.gd
~~~

Expected: all commands exit 0.

- [ ] **Step 5: Commit**

~~~bash
git add game/core/team_combo.gd game/core/team_score.gd game/levels/two_player_level.gd game/levels/coop_level.gd game/levels/sunny_forest.gd game/tests/unit/test_team_combo.gd game/tests/unit/test_world_rules.gd game/tests/integration/test_sunny_forest_action_combat.gd game/tests/integration/test_sunny_forest.gd
git commit -m "feat: add held fire and team combos"
~~~

---

### Task 6: Three Idempotent Secrets

**Files:**
- Create: game/world/secret_trigger.gd
- Create: game/world/secret_trigger.tscn
- Create: game/world/breakable_bramble.gd
- Create: game/world/breakable_bramble.tscn
- Create: game/art/objects/golden_carrot.svg
- Create: game/art/objects/cracked_bramble.svg
- Modify: game/tests/unit/test_spring_and_secrets.gd
- Modify: game/levels/sunny_forest.gd

**Interfaces:**
- Consumes: projectile overlaps, player overlaps, publish_world_event.
- Produces: SecretTrigger.discover(peer_id), discovered(secret_id, peer_id), BreakableBramble.try_projectile(projectile), SunnyForest.discover_secret and discovered_secret_count.

- [ ] **Step 1: Add failing idempotency tests**

~~~gdscript
var trigger = load("res://world/secret_trigger.gd").new()
trigger.secret_id = "momentum-carrot"
if not trigger.discover(1):
	_fail("first discovery must succeed")
	return
if trigger.discover(2):
	_fail("same secret must not discover twice")
	return
var restored = load("res://world/secret_trigger.gd").new()
restored.secret_id = "momentum-carrot"
if not restored.restore_state(trigger.snapshot_state()) or restored.discover(1):
	_fail("restored discovery must remain idempotent")
	return
~~~

Add a bramble test proving only an active basic/spread bubble breaks it and repeat hits do not re-emit broken.

- [ ] **Step 2: Run in red state**

~~~bash
godot --headless --path game -s res://tests/unit/test_spring_and_secrets.gd
~~~

Expected: FAIL on missing scripts.

- [ ] **Step 3: Implement local components and authority awards**

SecretTrigger validates non-empty id and peer 1/2, disables monitoring once, animates scale/fade, and snapshots {secret_id, discovered}. Restore requires the same id and boolean.

BreakableBramble accepts active BubbleProjectile with basic/spread kind, disables collision once, emits broken(bramble_id, owner_peer_id), and plays a bounded leaf burst. Sunny Forest owns discovered ids, publishes secret_discovered, awards secret:id once, advances combo, and plays the cue. The combat bramble reveals its carrot; momentum and co-op triggers begin visible. The co-op secret records two distinct peer ids on its two pads and requires both activations within a one-second window. Add secrets_found and secrets_total to the Sunny Forest completion payload without changing the shared results-screen contract.

- [ ] **Step 4: Run focused tests**

~~~bash
godot --headless --path game -s res://tests/unit/test_spring_and_secrets.gd
godot --headless --path game -s res://tests/integration/test_sunny_forest_action_combat.gd
~~~

Expected: both exit 0.

- [ ] **Step 5: Commit**

~~~bash
git add game/world/secret_trigger.gd game/world/secret_trigger.tscn game/world/breakable_bramble.gd game/world/breakable_bramble.tscn game/art/objects/golden_carrot.svg game/art/objects/cracked_bramble.svg game/levels/sunny_forest.gd game/tests/unit/test_spring_and_secrets.gd game/tests/integration/test_sunny_forest_action_combat.gd
git commit -m "feat: add optional forest secrets"
~~~

---

### Task 7: Re-author Sunny Forest and HUD Feedback

**Files:**
- Modify: game/levels/sunny_forest.tscn
- Modify: game/levels/sunny_forest.gd
- Modify: game/ui/gameplay_hud.gd
- Modify: game/ui/gameplay_hud.tscn
- Modify: game/levels/coop_level.gd
- Modify: game/visual/hero_visual.gd
- Modify: game/audio/audio_director.gd
- Modify: game/tests/integration/test_sunny_forest.gd
- Modify: game/tests/integration/test_hebrew_ui.gd
- Modify: game/tests/platform/test_sunny_forest_walk.gd
- Modify: game/tests/platform/test_sunny_forest_gates.gd
- Modify: game/tests/platform/test_sunny_forest_full.gd

**Interfaces:**
- Consumes: all mechanics from Tasks 1–6.
- Produces: sections SunlitMeadow, CanopyFork, FallenLogCrossing, BubbleGrove, MagicalTreeRun; safe_route/fast_route/spring_pad/secret groups; HUD render(score, rabbit_hearts, fox_hearts, powered_charges := 0, combo_multiplier := 1, secrets_found := 0, secrets_total := 0).

- [ ] **Step 1: Strengthen scene and HUD tests**

Require named sections, nonempty safe/fast route groups, at least three springs, exactly three secrets, four checkpoints, both enemy kinds, both existing co-op gates, and declared budgets 10/24/72.

Add HUD assertions:

~~~gdscript
hud.render(240, 2, 3, 7, 3, 2, 3)
if hud.get_node("Power/Count").text != "7":
	_fail("spread count must render")
	return
if hud.get_node("Combo").text != "×3" or not hud.get_node("Combo").visible:
	_fail("active combo must render")
	return
if hud.get_node("Secrets").text != "2/3":
	_fail("secret progress must render")
	return
hud.render(240, 2, 3, 0, 1, 0, 3)
if hud.get_node("Power").visible or hud.get_node("Combo").visible:
	_fail("inactive power and combo must hide")
	return
~~~

Retain Hebrew RTL assertions and physical LTR touch-control positions.

- [ ] **Step 2: Run in red state**

~~~bash
godot --headless --path game -s res://tests/integration/test_sunny_forest.gd
godot --headless --path game -s res://tests/integration/test_hebrew_ui.gd
~~~

Expected: FAIL on missing sections, groups, and HUD nodes.

- [ ] **Step 3: Author the five sections and feedback**

Extend level/camera limits to 4800 px. Place checkpoints near x=850, 2050, 3400, 4400.

- Sunlit Meadow 0–950: acceleration runway, safe star arc, one beetle, one seed, first spring.
- Canopy Fork 950–2050: continuous lower route, three upper platforms, two chained springs, momentum secret; every miss falls onto safe collision.
- Fallen Log Crossing 2050–3000: existing Foxy push and Riki switch after route reconvergence; bramble secret.
- Bubble Grove 3000–4000: spread flower, two seeds, two beetles, distinct-peer pressure flowers, co-op secret pads.
- Magical Tree Run 4000–4800: final spring/star chain, checkpoint, shared finish, trailing-partner runway.

Use 24–36 directional stars, <=10 enemies, exactly three secrets, and one bramble. Keep mandatory jumps reachable by both profiles.

Replace five ammo dots with one spread icon/count. Hide power at zero and combo at 1x; always show 0/3 secrets in Sunny Forest. Combo tween scales 1.25 to 1.0. Route distinct short cues and clamp camera impulses to shot 1 px, hit 2, defeat 4, spring 5, damage 8. Update platform timelines to traverse production physics; gate-isolation tests may reposition heroes, full-route tests may not.

- [ ] **Step 4: Run all scene/UI/platform regressions**

~~~bash
godot --headless --path game -s res://tests/integration/test_sunny_forest.gd
godot --headless --path game -s res://tests/integration/test_hebrew_ui.gd
godot --headless --path game -s res://tests/integration/test_results_flow.gd
godot --headless --path game -s res://tests/platform/test_sunny_forest_walk.gd -- --test=sunny_forest_walk --level=sunny_forest
godot --headless --path game -s res://tests/platform/test_sunny_forest_gates.gd -- --test=sunny_forest_gates --level=sunny_forest
godot --headless --path game -s res://tests/platform/test_sunny_forest_full.gd -- --test=sunny_forest_full --level=sunny_forest
~~~

Expected: all exit 0 and platform result JSON files report pass.

- [ ] **Step 5: Commit**

~~~bash
git add game/levels/sunny_forest.tscn game/levels/sunny_forest.gd game/ui/gameplay_hud.gd game/ui/gameplay_hud.tscn game/levels/coop_level.gd game/visual/hero_visual.gd game/audio/audio_director.gd game/assets/audio game/tests/integration/test_sunny_forest.gd game/tests/integration/test_hebrew_ui.gd game/tests/platform/test_sunny_forest_walk.gd game/tests/platform/test_sunny_forest_gates.gd game/tests/platform/test_sunny_forest_full.gd
git commit -m "feat: rebuild sunny forest around speed routes"
~~~

---

### Task 8: Rich Reconnect State and Protocol 2

**Files:**
- Create: game/tests/integration/test_sunny_forest_reconnect_rich_state.gd
- Modify: game/levels/sunny_forest.gd
- Modify: game/world/enemy_actor.gd
- Modify: game/world/bubble_projectile.gd
- Modify: game/core/team_combo.gd
- Modify: game/player/bubble_inventory.gd
- Modify: game/core/build_info.gd
- Modify: release/metadata.json
- Modify: game/tests/unit/test_project_smoke.gd
- Modify: game/tests/integration/test_sunny_forest.gd

**Interfaces:**
- Consumes: component snapshot APIs and world event sequence guard.
- Produces: snapshot keys weapons, combo, secrets, brambles; application protocol version 2.

- [ ] **Step 1: Write a failing rich-state round trip**

Set up ten spread charges, fire one fan, hurt a beetle once, score a star, discover one secret, and capture. Require keys:

~~~gdscript
for key in ["score", "collected_ids", "checkpoint_id", "heroes", "enemies", "gates", "weapons", "projectiles", "combo", "secrets", "brambles", "event_sequence"]:
	if not snapshot.has(key):
		_fail("rich snapshot missing %s" % key)
		return
if not level.restore_world_state(snapshot):
	_fail("valid rich snapshot must restore")
	return
if level.bubble_ammo.kind(1) != "spread" or level.bubble_ammo.remaining(1) != 9:
	_fail("powered state must restore")
	return
if level.active_bubble_count() != 3 or level.discovered_secret_count() != 1:
	_fail("fan and secret must restore")
	return
~~~

Corrupt enemy health, weapon kind, combo multiplier, duplicate secrets, and >24 projectiles separately. Each invalid snapshot must reject without partial mutation.

- [ ] **Step 2: Run in red state**

~~~bash
godot --headless --path game -s res://tests/integration/test_sunny_forest_reconnect_rich_state.gd
~~~

Expected: FAIL on missing rich keys.

- [ ] **Step 3: Implement validate-then-commit restore and bump protocol**

Validate all sections into temporary values before mutating live state. Reject unknown kinds, health outside bounds, combo outside 1–4, timer outside 0–2.5, duplicate secrets, wrong bramble ids, or >24 projectiles. Restore never emits score/discovery signals.

Set application_protocol_version to 2 in release/metadata.json and run:

~~~bash
python3 scripts/sync_release_metadata.py --write
~~~

Update test_project_smoke expectations. Keep save_schema_version at 1 because session state is not persisted.

- [ ] **Step 4: Run reconnect and compatibility checks**

~~~bash
godot --headless --path game -s res://tests/integration/test_sunny_forest_reconnect_rich_state.gd
godot --headless --path game -s res://tests/unit/test_project_smoke.gd
godot --headless --path game -s res://tests/unit/test_protocol.gd
python3 scripts/sync_release_metadata.py --check
bash scripts/run_lan_pair.sh
bash scripts/run_reconnect_pair.sh
~~~

Expected: all exit 0 and pair logs report compatible protocol-2 peers.

- [ ] **Step 5: Commit**

~~~bash
git add game/levels/sunny_forest.gd game/world/enemy_actor.gd game/world/bubble_projectile.gd game/core/team_combo.gd game/player/bubble_inventory.gd game/core/build_info.gd release/metadata.json game/tests/unit/test_project_smoke.gd game/tests/integration/test_sunny_forest.gd game/tests/integration/test_sunny_forest_reconnect_rich_state.gd
git commit -m "feat: restore rich forest combat state"
~~~

---

### Task 9: Platform Coverage and Release Gates

**Files:**
- Create: game/tests/platform/test_sunny_forest_momentum_combat.gd
- Modify: game/tests/platform/test_runner.gd
- Modify: game/tests/device/performance_check.gd
- Modify: docs/release-checklist.md
- Modify: game/assets/ATTRIBUTION.md if its existing convention lists self-authored assets

**Interfaces:**
- Consumes: final Sunny Forest and input-timeline harness.
- Produces: captures canopy_speed, spread_combat, secret_found, tree_finish; automated budget proof; explicit unpassed device/usability gate.

- [ ] **Step 1: Write failing platform assertions**

Create a timeline that drives both heroes through the opening, holds fire at a beetle, takes Riki over the upper springs, collects the momentum secret, acquires spread fire, and reunites at finish. Capture the four exact names above. Add assertion kinds:

~~~gdscript
"active_projectiles_lte":
	passed = _level.active_bubble_count() <= int(args[0])
	message = "active projectiles=%d <= %d" % [_level.active_bubble_count(), int(args[0])]
"secrets_eq":
	passed = _level.discovered_secret_count() == int(args[0])
	message = "secrets=%d == %d" % [_level.discovered_secret_count(), int(args[0])]
"combo_lte":
	passed = int(_level.team_combo.multiplier) <= int(args[0])
	message = "combo=%d <= %d" % [int(_level.team_combo.multiplier), int(args[0])]
~~~

End assertions: score_gt 0, active_projectiles_lte 24, secrets_eq 1, combo_lte 4, finished true, no_errors. Extend performance_check to instantiate Sunny Forest after Cloud Factory and enforce declared budgets <=12/24/80.

- [ ] **Step 2: Run in red state**

~~~bash
godot --headless --path game -s res://tests/platform/test_sunny_forest_momentum_combat.gd -- --test=sunny_forest_momentum_combat --level=sunny_forest
godot --headless --path game -s res://tests/device/performance_check.gd
~~~

Expected: platform FAIL until assertion support/frame counts are correct; budget FAIL if scene budgets are absent.

- [ ] **Step 3: Finish deterministic captures and document human gates**

Tune only timeline input durations/assertion frames; do not teleport in this full-route test. With DISPLAY, run and visually inspect baselines:

~~~bash
python3 scripts/run_visual_tests.py --update-baselines
~~~

Add unchecked release-checklist items for: two children/operators completing safe route; one completing fast route; both finding one secret without instruction; both understanding held fire; both tablets maintaining >=30 FPS through Canopy Fork and Bubble Grove. Never mark human/hardware gates passed from automation.

- [ ] **Step 4: Run the complete verification ladder**

~~~bash
godot --headless --path game -s res://tests/platform/test_sunny_forest_momentum_combat.gd -- --test=sunny_forest_momentum_combat --level=sunny_forest
godot --headless --path game -s res://tests/device/performance_check.gd
bash scripts/test_all.sh
python3 -m unittest discover -s deploy/tests -t . -p 'test_*.py' -v
python3 -m deploy.animal_heroes_deploy --check
bash scripts/build_android.sh
~~~

Expected: all exit 0; build emits APK, sha256, and idsig; permission audit reports exactly four allowed permissions. If toolchain pieces are missing, report the exact error and do not claim that gate.

- [ ] **Step 5: Commit and stop at hardware boundary**

~~~bash
git add game/tests/platform/test_sunny_forest_momentum_combat.gd game/tests/platform/test_runner.gd game/tests/device/performance_check.gd test-output/baselines/sunny_forest_momentum_combat docs/release-checklist.md game/assets/ATTRIBUTION.md
git commit -m "test: gate energetic sunny forest gameplay"
~~~

Do not run device_smoke.sh without two resolved SM-T220 serials and a human for the ten-minute gameplay interval.

## Final Review Checklist

- [ ] Every design acceptance criterion maps to Tasks 1–9.
- [ ] git diff --check reports no whitespace errors.
- [ ] git status --short shows no accidentally staged operator evidence or game/test-output.
- [ ] Full game, LAN, reconnect, performance, permission, deploy, and build commands have real recorded exit status.
- [ ] New original assets follow game/assets/ATTRIBUTION.md conventions.
- [ ] Physical-tablet FPS and child usability remain unchecked until humans perform them.
