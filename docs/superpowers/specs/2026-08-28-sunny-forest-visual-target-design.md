# Sunny Forest Visual Target — Design Specification

Date: 2026-08-28
Status: Approved

## 1. Purpose

Transform the existing geometric test arena into the visual-quality target for Animal Heroes. This first polished arena establishes the art language, reusable scene structure, animation conventions, and performance budget for later levels.

The target is a bright, polished children's platformer with the energy of the supplied reference: saturated color, rounded silhouettes, expressive animal heroes, layered natural scenery, chunky grass-topped platforms, friendly collectibles, and soft glossy effects. All characters, shapes, layouts, and assets must remain original rather than reproducing the reference image.

## 2. Chosen Approach

Use a lightweight hybrid art pipeline:

- Original illustrated SVG assets provide crisp characters, platforms, foliage, clouds, collectibles, and interface symbols at the target tablet resolution.
- Godot composes these assets into reusable scenes and supplies movement, squash-and-stretch, bobbing, glow, particles, and parallax.
- Collision and gameplay logic remain separate from presentation so visual iteration cannot change movement rules accidentally.
- SVG complexity, transparency, particles, and draw calls stay conservative for the Samsung Galaxy Tab A7 Lite SM-T220.

This approach was selected over two alternatives:

1. Procedural Godot polygons would be fastest and cheapest but would not reach the illustrated character and environmental finish of the reference.
2. Large raster spritesheets could provide richer frame-by-frame animation but would consume more texture memory and production time than this first visual target warrants.

## 3. Visual Language

### Shape and line

- Heroes, collectibles, controls, and important interactables use large rounded silhouettes and dark blue-black outlines.
- Outlines are consistent within each asset class and remain legible at normal gameplay scale.
- Scenery uses softer internal edges and less contrast than gameplay objects.
- Small decorative detail is avoided when it would disappear on the tablet or compete with the heroes.

### Color

- The palette is saturated but organized: cyan-to-royal-blue sky, lime-to-emerald foliage, warm ochre rock, and bright orange/yellow rewards.
- Foreground gameplay elements carry the strongest contrast.
- Background layers become cooler, lighter, and less detailed with distance.
- Rabbit and fox clothing colors are distinct from one another and from the dominant environment colors.

### Light and depth

- Soft upper-left highlights and restrained lower-right shading create a glossy cartoon volume.
- Platforms use three readable material bands: bright grass cap, warm soil/rock face, and darker underside.
- Decorative sparkles and glow are localized around rewards and effects; there are no expensive full-screen shaders.

## 4. Hero Design

### Riki the Rabbit

- White rabbit with oversized expressive ears, a compact rounded muzzle, and a clearly readable happy face.
- Red top, blue shorts, and light shoes establish a strong red/blue identity.
- The ears, face direction, and body lean make movement direction readable even without animation.

### Foxy the Fox

- Orange fox with cream muzzle, chest, ear interiors, and tail tip.
- Green top, dark shorts, and light shoes establish a green/orange identity.
- The large tail supplies a distinctive silhouette and may lag subtly during motion.

### Animation set

The first visual target uses economical transform and pose animation rather than a large frame set:

- Idle: breathing, occasional blink, small ear or tail secondary motion.
- Run: body bob, alternating foot poses, forward lean, and light squash/stretch.
- Jump: anticipation squash, stretched ascent pose, compact fall pose, and soft landing squash.
- Action: short forward gesture with a readable effect origin.
- Damage/respawn: brief non-flashing recoil followed by a cheerful recovery.

Animations must remain responsive: presentation never delays physics or input.

## 5. Sunny Forest Environment

The arena is composed in landscape layers:

1. A saturated blue sky gradient with soft rounded clouds.
2. Distant cool blue-green hills and tree silhouettes.
3. Midground rounded forest shapes that scroll more slowly than gameplay.
4. Playable floating platforms with bright grass caps and chunky faceted rock.
5. Foreground leaf clusters, flowers, and occasional mushrooms framing screen edges without hiding hazards or controls.

The arena layout and collisions remain recognizable during the visual conversion. Decorative elements must not imply traversable surfaces where none exist.

## 6. Collectibles and Effects

- Stars use a rounded five-point silhouette, warm yellow center, orange rim, small friendly face, and a subtle highlight.
- Each star bobs gently and emits a small bounded sparkle effect.
- Bubble effects use a blue-white rim, transparent center, one or two highlights, and a short motion streak only while moving.
- Collection uses a quick scale pop and a small reusable sparkle burst.
- The checkpoint becomes a cheerful, unmistakable forest marker with a brief activation glow.

Effects use pooled or bounded particles. No effect can obscure a hero or touch control.

## 7. Interface Treatment

- Touch controls remain in their current corners and retain their 128-pixel minimum targets.
- Buttons become rounded translucent blue panels with thick pale borders and simple high-contrast icons.
- Hebrew labels remain available where useful, but the jump and action buttons gain clear visual symbols so a child does not need to read.
- Controls sit above scenery with enough opacity and shadow to remain visible over both sky and foliage.
- Partner indicators adopt the same rounded outline and color language as collectibles and controls.

## 8. Scene and Asset Structure

Presentation is separated into reusable units:

- `game/art/characters/`: original rabbit and fox SVG parts or compact pose assets.
- `game/art/environment/sunny_forest/`: sky, clouds, hills, foliage, platform surfaces, flowers, and mushrooms.
- `game/art/collectibles/`: stars, bubbles, sparkles, and checkpoint art.
- `game/art/ui/`: movement, jump, action, and partner-indicator symbols.
- `game/visual/hero_visual.gd`: direction, pose, squash/stretch, and secondary motion driven from player state.
- `game/visual/collectible_visual.gd`: idle bob, glow, and collection response.
- `game/visual/sunny_forest_background.tscn`: layered parallax scenery.
- `game/theme/`: shared colors and interface style resources.

Existing physics nodes, scripts, profiles, checkpoints, and tests remain authoritative. Visual scenes are children or presentation siblings of gameplay nodes and do not become dependencies of gameplay rules.

## 9. Performance Budget

- Maintain at least 30 FPS on both target SM-T220 tablets.
- Avoid full-screen shaders, dynamic 2D lights, large blur filters, and unbounded particles.
- Prefer shared textures/materials and reusable scenes.
- Keep decorative animation rates and particle counts modest.
- Import SVGs at practical gameplay sizes rather than excessive resolution.
- Verify worst-case overdraw where foreground foliage, controls, effects, and both heroes overlap.

## 10. Testing and Verification

Automated verification will cover:

- The arena still loads headlessly.
- Both hero gameplay nodes retain collision, profiles, cameras, and input behavior after visual children are replaced.
- Collectible and platform groups/counts remain intact.
- Touch targets remain at least 128 by 128 pixels and preserve expected signals.
- Visual animation scripts tolerate missing optional nodes and do not affect physics state.

Visual verification will include:

- A rendered landscape screenshot at 1340 by 800 compared against this specification.
- Readability checks for hero silhouettes, traversable surfaces, stars, checkpoint, partner indicator, and controls.
- Inspection at the approximate physical size of the Galaxy Tab A7 Lite display.
- A gameplay run confirming visual animation does not change movement timing.
- Physical-device frame-rate and overdraw validation before the visual target is declared final.

## 11. Acceptance Criteria

The visual target is complete when:

1. The test arena presents an original polished Sunny Forest scene rather than placeholder polygons.
2. Rabbit and fox are immediately distinguishable, expressive, and readable in motion.
3. The scene clearly matches the approved language: saturated cartoon color, rounded silhouettes, outlined heroes and rewards, layered depth, grass-topped rock platforms, and friendly glossy effects.
4. Gameplay surfaces and collectibles remain unambiguous despite the additional detail.
5. Touch controls remain readable and usable over every background region.
6. Existing automated tests pass and gameplay behavior is unchanged.
7. The scene meets the 30 FPS target on the two SM-T220 devices.
8. All created art is original and does not reproduce the reference's exact characters, poses, or composition.

## 12. Out of Scope

- Rebuilding the arena layout or movement rules.
- Producing final art for Crystal Caves, Cloud Factory, boss, or competitive arenas.
- Creating a large frame-by-frame animation library.
- Adding new gameplay, networking, audio, or progression behavior.
- Shipping the Android release build as part of this visual-target task.
