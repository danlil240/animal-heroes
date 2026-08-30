extends "res://tests/platform/test_runner.gd"


## Momentum-and-combat coverage for the re-authored Sunny Forest. Drives both
## heroes through the spring pads, a spread-fire combat encounter, a secret
## discovery, and the magical-tree finish. Asserts the entity budgets, exactly
## one secret found, combo ceiling, positive score, finish, and no errors.
func _build_timeline() -> InputTimeline:
	var t := InputTimeline.new(640)
	# Fox (peer 2): walk right, push the fallen log, pick up the bubble flower,
	# fire spread at the bramble to reveal the combat secret, then continue to
	# the magical tree.
	t.add(2, 0, 560, {"axis": 1.0})
	t.add(2, 561, 640, {"axis": 0.0})
	t.add(2, 117, 117, {"action": true})
	t.add(2, 119, 119, {"action": true})
	t.add(2, 121, 121, {"action": true})
	t.add(2, 123, 123, {"action": true})
	t.add(2, 125, 125, {"action": true})
	t.add(2, 127, 127, {"action": true})
	t.add(2, 129, 129, {"action": true})
	# Jump onto Platform6 and fire at the bramble/combat secret area.
	t.add(2, 200, 205, {"jump": true})
	t.add(2, 222, 222, {"action": true})
	t.add(2, 224, 224, {"action": true})
	t.add(2, 226, 226, {"action": true})
	# Jump over SeedGrove1 and continue rightward.
	t.add(2, 295, 300, {"jump": true})
	t.add(2, 265, 265, {"action": true})
	t.add(2, 267, 267, {"action": true})
	t.add(2, 269, 269, {"action": true})
	t.add(2, 281, 281, {"action": true})
	t.add(2, 283, 283, {"action": true})
	t.add(2, 285, 285, {"action": true})
	# Rabbit (peer 1): spring up to the canopy, grab the momentum secret,
	# activate the overhead switch, then continue to the magical tree.
	t.add(1, 0, 150, {"axis": 1.0})
	t.add(1, 151, 155, {"axis": 0.0})
	t.add(1, 156, 560, {"axis": 1.0})
	t.add(1, 561, 640, {"axis": 0.0})
	t.add(1, 5, 10, {"jump": true})
	t.add(1, 45, 50, {"jump": true})
	t.add(1, 115, 120, {"jump": true})
	t.add(1, 151, 151, {"action": true})
	t.add(1, 153, 153, {"action": true})
	t.add(1, 155, 155, {"action": true})
	t.add(1, 241, 241, {"action": true})
	t.add(1, 243, 243, {"action": true})
	t.add(1, 245, 245, {"action": true})
	t.capture(120, "canopy_speed")
	t.capture(240, "spread_combat")
	t.capture(320, "secret_found")
	t.capture(560, "tree_finish")
	t.assert_end("score_gt", [0])
	t.assert_end("active_projectiles_lte", [24])
	t.assert_end("secrets_eq", [1])
	t.assert_end("combo_lte", [4])
	t.assert_end("finished")
	t.assert_end("no_errors")
	t.assert_end("both_alive")
	return t
