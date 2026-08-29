# Changelog

All notable changes to Animal Heroes are documented in this file.

## [Unreleased] — 1.0.0 release candidate

### Added

- Godot 4 project with typed GDScript, headless test harness, and atomic save data
- Rabbit and fox player movement with profiles, health, respawn, and coyote/buffer jumps
- Hebrew RTL main menu, tutorial, and touch controls with 96+ px targets
- Offline two-player test arena with partner indicator and independent cameras
- UDP broadcast host discovery with compatibility filtering
- ENet host/client session lifecycle with explicit state graph
- Host-authoritative input replication with interpolation and reconciliation
- Pause, reconnect, and confirmed checkpoint recovery (15-second retry window)
- Cooperative world mechanics: interactables, enemies, object pool, powerups
- Sunny Forest cooperative level (4 checkpoints, 2 enemy types, bubble powerup)
- Crystal Caves cooperative level (moving platforms, paired switches, heavy push)
- Cloud Factory cooperative level (fans, conveyors, boss entrance, entity budgets)
- Comical robot boss with deterministic phase machine and checkpointed retries
- Star Race competitive mode (4 checkpoints, 15-second grace period)
- Treasure Dash competitive mode (180-second timer, bounded collectible spawning)
- Bubble Bounce competitive mode (hit scoring, repeated-hit protection)
- Positive Hebrew results screen with synchronized rematch flow
- Sunny Forest visual target: original SVG art, layered parallax background,
  animated hero visuals, friendly star/checkpoint visuals, illustrated controls
- Visual target extended to all cooperative and competitive levels
- Audio director with independent Music/SFX buses and persisted settings
- Android export configuration with LAN-only permissions
- Android build script, permission audit, and device smoke test harness
- Performance check test for entity budget verification
- Release checklist, SM-T220 performance doc, and child usability test plan
- Android application icon and smoke contract for its configured, loadable SVG
- Release metadata reconciled with the installed Godot, Java, and Android toolchain

### Pending

- Physical SM-T220 tablet endurance and FPS validation
- Supervised child usability sessions
- Signed release APK build (requires keystore)
- Creator and distribution-rights provenance for all shipped WAV assets
