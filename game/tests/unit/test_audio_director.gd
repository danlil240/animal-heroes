extends SceneTree

## Reproduces the projectile voice signal double-connect bug in AudioDirector.
## When play_sfx(path, true) reuses an SFX player that still has a pending
## CONNECT_ONE_SHOT `finished` connection, connect() errors and the
## _projectile_voices_in_use counter drifts above the real connection count,
## eventually blocking all projectile sounds.

const SFX_GAMEPLAY := "res://assets/audio/sfx_gameplay.wav"

func _init() -> void:
	var script: Script = load("res://audio/audio_director.gd")
	if script == null:
		push_error("AudioDirector script is missing")
		quit(1)
		return

	var director: Node = script.new()
	root.add_child(director)
	director._setup_players()
	var passed := _test_projectile_reuse_keeps_counter_consistent(director)
	director.free()
	if not passed:
		quit(1)
		return
	quit(0)


## Calling play_sfx with is_projectile=true on a player that was stopped (not
## finished naturally) must keep _projectile_voices_in_use equal to the actual
## number of pending finished connections. Before the fix, stop() makes the
## player available again without emitting `finished`, so the one-shot is still
## connected — the next connect() errors and the counter inflates beyond the
## real connection count, eventually blocking all projectile sounds.
func _test_projectile_reuse_keeps_counter_consistent(director: Node) -> bool:
	# First projectile shot grabs a player and connects finished.
	director.play_sfx(SFX_GAMEPLAY, true)
	# Simulate the stream ending without `finished` firing (e.g. very short
	# clip, frame timing, or stream replacement) by stopping the player.
	var players: Array = director.get("_sfx_players")
	players[0].stop()
	# Second shot reuses the same now-available player.
	director.play_sfx(SFX_GAMEPLAY, true)
	players[0].stop()
	# Third reuse.
	director.play_sfx(SFX_GAMEPLAY, true)

	var counter: int = int(director.get("_projectile_voices_in_use"))
	var actual_connections := _count_projectile_connections(director)
	if counter != actual_connections:
		push_error("projectile voice counter (%d) != actual finished connections (%d); counter drifted" % [counter, actual_connections])
		return false
	if counter > director.MAX_PROJECTILE_VOICES:
		push_error("projectile voice counter (%d) exceeded MAX_PROJECTILE_VOICES (%d)" % [counter, director.MAX_PROJECTILE_VOICES])
		return false
	return true


func _count_projectile_connections(director: Node) -> int:
	var count := 0
	for player in director.get("_sfx_players"):
		if player.finished.is_connected(director._on_projectile_voice_finished):
			count += 1
	return count
