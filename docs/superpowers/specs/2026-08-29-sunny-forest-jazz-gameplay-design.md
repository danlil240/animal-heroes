# Sunny Forest Momentum, Combat, and Secrets Design

**Date:** 2026-08-29  
**Status:** Approved direction  
**Scope:** One polished Sunny Forest gameplay vertical slice

## Summary

Animal Heroes already has a complete campaign skeleton, network play, touch
controls, co-op gates, enemies, collectibles, and a visual testing platform.
The next release should deepen the moment-to-moment play instead of adding more
modes. Sunny Forest will become the reference-quality vertical slice: fast,
expressive movement leads into playful ranged combat and opens optional routes
with secrets.

The target is the *energy and readability* of a polished 1990s action
platformer, not a copy of Jazz Jackrabbit's characters, art, levels, weapons,
music, or other protected expression. All new presentation remains original,
child-friendly, Hebrew-compatible, and suitable for two SM-T220 tablets.

## Goals

- Make moving across an empty stretch enjoyable through acceleration,
  momentum, variable jumping, and responsive audiovisual feedback.
- Make combat frequent, readable, forgiving, and satisfying without realistic
  violence.
- Reward speed, observation, shooting, and cooperation with optional routes
  and secrets.
- Preserve the existing four-button touch layout: left, right, jump, action.
- Preserve host authority, reconnect reconstruction, deterministic tests, and
  current Android entity budgets.
- Produce reusable gameplay primitives that later levels can adopt without
  redesigning them during this slice.

## Non-goals

- Reworking Crystal Caves, Cloud Factory, the boss, or competitive modes.
- Adding a dash, weapon-select, aim, or inventory button.
- Adding online services, third-party dependencies, or copyrighted assets.
- Changing physics or network tick rates to improve apparent performance.
- Building a general-purpose ability framework before a second use exists.
- Replacing the campaign progression, scoring, pause, results, or deployment
  systems.

## Chosen Approach

Use a mechanics-first vertical slice. Movement, firing, hit response, combo
scoring, springs, and secrets are implemented as small reusable units, but only
Sunny Forest is re-authored to use all of them now.

This is preferable to a content-first pass because more enemies on top of flat
movement would not improve every second of play. It is preferable to a
whole-campaign retrofit because movement, combat cadence, touch ergonomics, LAN
replication, and tablet performance need to be proven together before they are
copied into six other modes.

## Player Experience

The intended session lasts roughly three to five minutes for children familiar
with the controls. The opening meadow teaches acceleration, a long jump, and a
stomp without text. A line of stars curves through the safest route while a
visibly higher route invites confident players to preserve speed across
springs. Enemies then appear in arrangements that let a held blaster clear a
path without forcing the player to stop.

The middle of the level alternates short speed runs with a co-op gate and a
compact combat grove. A temporary spread-bubble pickup creates an obvious power
spike. Three optional secrets reward different skills: maintaining momentum,
shooting through a breakable bramble, and coordinating both heroes. The finish
retains the magical tree and requires both heroes, so exploration never strands
one player at an irreversible exit.

## Controls and Context Priority

The existing touch layout remains unchanged.

- Left and right control horizontal movement.
- Jump supports buffering, coyote time, and variable height.
- Pressing action near an eligible interactable performs that interaction once.
- Pressing or holding action without an eligible interactable fires immediately
  and then repeats at a fixed cadence.
- An interaction consumes that press and suppresses firing until action is
  released, preventing accidental shots while using gates or pickups.
- Keyboard mappings continue to mirror touch behavior for tests and desktop
  play.

This rule keeps controls understandable for children: the action button always
does the most relevant nearby thing, and otherwise it shoots.

## Movement Model

`PlayerBody` changes from instant horizontal velocity to a tuned acceleration
model. Profile resources own the small set of character-specific values:
maximum run speed, ground acceleration, ground deceleration, air acceleration,
jump speed, and the existing health/heavy-push capability.

- Riki remains slightly faster and jumps slightly higher.
- Foxy remains slightly slower, has one extra heart, and can push heavy objects.
- Full directional input reaches at least 90% of maximum speed within 0.35
  seconds.
- Releasing input from maximum speed stops the hero within 80 pixels on level
  ground.
- Reversing direction brakes first and then accelerates, making direction
  changes responsive without erasing all sense of momentum.
- Air control is strong enough to correct a jump but weaker than ground control.
- Releasing jump early applies an additional downward force. A held jump's apex
  must be at least 25% higher than a tapped jump's apex.
- Existing 100 ms coyote time and 120 ms jump buffering remain.
- Stomping a live enemy applies a consistent upward rebound so players can chain
  traversal and combat.

The level adds spring pads as the only new traversal object. They apply a fixed
authoritative launch velocity and have a clear compressed/extended visual
state. There is no dash button or stamina system.

Presentation follows state instead of controlling it. Hero visuals add a lean
at high speed, stronger takeoff/landing squash, a short dust trail on ground,
and a restrained speed streak above the top speed tier. The local camera gains
horizontal look-ahead based on velocity and smooths back toward the hero when
the player stops. Camera shake is local, subtle, and triggered only by damage,
strong enemy defeats, and spring launches.

## Combat Model

Every hero always has an unlimited basic bubble shot. This removes the current
failure mode where combat disappears after five shots. Firing is capped at five
shots per second, begins on the press frame, and uses the existing facing
direction. No manual aiming is added.

The Bubble Flower grants a temporary spread-bubble mode with ten powered shots.
Each powered shot emits three small projectiles in a shallow fan but consumes
one powered charge. When the charges reach zero, firing automatically returns
to the basic shot. The HUD shows the spread icon and remaining powered charges;
it does not display ammunition for the unlimited basic shot.

The projectile pool is expanded only as required and the total active
projectile budget remains at or below 24. Projectiles expire after a bounded
lifetime and release cleanly to the pool. A single firing command includes the
weapon kind and authoritative shot sequence so peers reconstruct the same fan.

Enemy hits become multi-stage feedback rather than instant deletion:

- Seed enemies have one hit point and reward quick reactions.
- Beetles have two hit points, briefly recoil on the first hit, then resume
  patrol.
- A hurt enemy flashes, is pushed a short bounded distance, ignores additional
  hits for a brief invulnerability window, and retains its collision.
- Defeat disables collision once, emits one authoritative score event, plays an
  original burst animation and sound, and returns no persistent gore or debris.
- Contact damage, spawn protection, and respawn behavior remain unchanged.

Hit pause is deliberately excluded because freezing one peer would complicate
network presentation. Punch comes from recoil, flash, sound, particles, score
popups, and small local camera impulses.

## Combo and Scoring

Enemy defeats and star pickups extend one shared team combo window. Each scored
event within 2.5 seconds advances the multiplier up to 4x; expiration resets it
to 1x. Teamwork gate bonuses do not multiply and instead refresh the timer,
avoiding extreme score inflation from one scripted event.

The host owns combo state. The gameplay HUD displays the multiplier only above
1x and animates it on increases. Results continue to consume the final team
score, so no results-screen contract changes are required.

## Sunny Forest Layout

The level remains a left-to-right forest and retains its named teaching beats,
four checkpoints, two-character gate, Bubble Grove pressure gate, and magical
tree finish. Its geometry is re-authored into five compact sections:

1. **Sunlit Meadow:** safe acceleration runway, star arc, first spring, one
   beetle, and a stomp setup.
2. **Canopy Fork:** a safe lower route and a faster upper route connected by
   springs. Falling returns the player to the lower route rather than killing
   them.
3. **Fallen Log Crossing:** existing Foxy push and Riki overhead-switch roles,
   positioned so both paths reconverge before the barrier.
4. **Bubble Grove:** spread-bubble pickup followed by a short combat formation
   and the existing two-player pressure flowers.
5. **Magical Tree Run:** one final momentum chain, a visible secret tease, the
   fourth checkpoint, and the shared finish.

The authored population stays within the existing worst-case limits: no more
than 12 enemies, 24 active projectiles, or 80 particles. Hazards and secrets
must not depend on frame-perfect jumps. Checkpoints sit after major teaching
beats rather than before every obstacle.

## Secrets and Route Communication

Sunny Forest contains exactly three optional golden-carrot secrets:

- **Momentum secret:** reached by carrying speed through the Canopy Fork spring
  chain.
- **Combat secret:** revealed by shooting a clearly cracked bramble barrier.
- **Co-op secret:** opened when both heroes stand on a pair of optional flower
  pads within the same window.

Secret discovery is permanent for the current run, awards a fixed team bonus,
and shows `1/3`, `2/3`, or `3/3` in the HUD. Secrets are included in reconnect
state and the completion result payload. They are never required to open a
checkpoint, gate, or exit.

Star placement communicates traversal rather than decorating every surface:
single-file arcs show safe jumps, dense chains mark fast routes, and small
clusters tease secret entrances. The partner indicator remains available when
routes separate.

## Components and Ownership

The implementation should use the narrowest responsible owners:

- `PlayerProfile` stores character tuning values.
- `PlayerBody` owns acceleration, deceleration, air control, variable jump, and
  stomp rebound application.
- `SunnyForest` resolves interaction-versus-fire priority, authoritative firing
  cadence, powered-shot state, combo state, secrets, scoring, and snapshot
  integration.
- `BubbleProjectile` owns one projectile's movement, kind, lifetime, collision,
  and pool release.
- `EnemyActor` owns health, hurt cooldown, recoil, defeat, and serializable
  combat state.
- A small `SpringPad` world component owns eligibility, launch velocity, and
  visual-state notification.
- A small `SecretTrigger` or breakable-bramble component owns only its local
  activation rule and emits an id; Sunny Forest owns authoritative award and
  persistence.
- `GameplayHud` presents powered shots, combo, and secret count.
- `HeroVisual`, enemy visuals, and new world visuals react to exposed gameplay
  state without mutating rules.

No general combat framework or inheritance hierarchy is introduced. If later
levels adopt these mechanics, extraction happens only when a second owner
actually needs the behavior.

## Authority, Replication, and Reconnect

The host remains authoritative for enemies, shots, scoring, gates, and secrets.
The existing player input stream already carries held action state; the host
derives fire cadence from that state and rejects firing while the same press is
claimed by an interaction.

World actions and snapshots gain the minimum additional fields needed to
reconstruct play:

- Projectile entries include projectile kind and fan member identity.
- Enemy entries include health, hurt cooldown, direction, motion state,
  position, and velocity.
- Per-player weapon entries include powered weapon kind and remaining charges.
- Combo includes multiplier and remaining window.
- Secrets include the collected secret ids and state of the breakable bramble
  and optional co-op pads.
- Spring pads need no persistent state; their animation can recover to idle.

Snapshot restoration validates types, clamps bounded numeric values, rejects
unknown weapon kinds, and does not re-emit score or discovery signals. Existing
sequence checks continue to prevent duplicate world events. The network
protocol version is incremented only if the serialized wire contract changes;
metadata synchronization remains mandatory.

## Failure and Edge Cases

- Projectile-pool exhaustion rejects the shot without consuming a powered
  charge and logs a bounded diagnostic in debug builds.
- A disconnected peer cannot leave an interaction press latched; input reset
  clears action and repeat-fire state.
- Multiple projectiles hitting one enemy during its hurt cooldown cannot award
  duplicate score or combo increments.
- A player inside an interaction radius cannot fire until action is released,
  even if the target disappears during that press.
- Respawning clears held-action repeat timing but preserves the host-owned
  powered-shot count.
- Falling from the upper route lands on the safe route or respawns at the last
  confirmed checkpoint; secrets already collected remain collected.
- Reconnect restore never grants powered shots, combo points, or secrets twice.
- Both heroes can complete every mandatory route regardless of their different
  speed and jump values.

## Accessibility and Child Usability

- No new touch targets are added and existing targets remain at least 96 px.
- Fast routes are optional; the lower route remains forgiving.
- Important interactions keep their Hebrew context label and visual pulse.
- Color is never the only signal for enemy hurt, powered shots, or secrets;
  silhouette, motion, icon, and sound reinforce state.
- Flash and shake are brief and low amplitude, with no full-screen strobe.
- Failure returns players quickly to the latest shared checkpoint without
  uninstalling, clearing, or mutating saved progress.

## Testing Strategy

Implementation follows test-first slices.

### Unit tests

- Acceleration reaches the speed target, release stops within the distance
  bound, reversal brakes correctly, and air control stays below ground control.
- Held and tapped jumps preserve coyote/buffer behavior and meet the 25% apex
  separation.
- Held action fires immediately, respects the five-per-second cap, and requires
  release after an interaction consumes a press.
- Powered fire emits three deterministic fan members, consumes one charge, and
  falls back to basic fire at zero.
- Enemy health, hurt cooldown, recoil, and one-time defeat scoring are stable
  under simultaneous-hit attempts.
- Combo advances, caps at 4x, expires after 2.5 seconds, and excludes teamwork
  bonuses from multiplication.
- Secret ids award once and restore without duplicate signals.

### Integration and platform tests

- Both profiles can traverse every mandatory platform and activate their
  existing role-gated interactions.
- The level exposes both safe and fast routes, exactly three optional secrets,
  at least four checkpoints, both enemy types, a spring, a powered-shot pickup,
  and the two-player finish.
- Full Sunny Forest playback covers acceleration, a spring launch, basic fire,
  powered fire, an enemy hurt/defeat sequence, one secret, a co-op gate, and
  completion.
- Golden screenshots cover the Canopy Fork, powered combat, secret discovery,
  and finish while preserving the existing sunny-forest visual gates.
- Reconnect restores a mid-combat snapshot containing an injured enemy,
  in-flight fan projectiles, powered charges, combo, and one collected secret.
- LAN pair and reconnect pair tests remain green.

### Performance and release gates

- `performance_check.gd` continues to enforce 12 enemies, 24 projectiles, and
  80 particles in the worst-case scene.
- `bash scripts/test_all.sh` and the deploy unit suite pass before completion is
  claimed.
- A debug APK passes the unchanged exact permission audit.
- Real-device smoke verifies a minimum of 30 FPS on both SM-T220 tablets during
  operator-driven traversal of the Canopy Fork and Bubble Grove. Automated
  tests do not substitute for that hardware evidence.

## Acceptance Criteria

The vertical slice is complete when all of the following are true:

- Existing left/right/jump/action controls can perform every new mechanic.
- Both heroes use acceleration-based movement, variable jump height, air
  control, and stomp rebounds while retaining their profile differences.
- Sunny Forest contains one safe route, one meaningfully faster optional route,
  spring-assisted traversal, a combat sequence, and three optional secrets.
- Players can always fire a basic bubble; the Bubble Flower grants ten
  three-projectile spread shots and automatically falls back at zero.
- Seeds and beetles demonstrate distinct durability with clear hurt, recoil,
  and defeat feedback.
- Shared combo reaches at most 4x, expires predictably, and is visible only when
  active.
- All new authoritative state survives snapshot/restore without duplicate
  rewards.
- Mandatory content is completable by either profile and optional speed content
  is forgiving of a missed jump.
- Entity budgets, permission audit, full automated suite, and deploy tests pass.
- On-device performance and child usability remain explicit human-operated
  gates rather than inferred claims.

## Delivery Boundary

This slice ends after Sunny Forest, its shared primitives, automated coverage,
and device-ready build are complete. Porting the mechanics into Crystal Caves,
Cloud Factory, the boss, or competitive modes requires a separate design based
on evidence from this slice.
