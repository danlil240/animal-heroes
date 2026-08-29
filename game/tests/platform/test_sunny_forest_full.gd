extends "res://tests/platform/test_runner.gd"


func _build_timeline() -> InputTimeline:
	var t := InputTimeline.new(480)
	# Fox (peer 2): push FallenLog, pick up bubble power-up, activate RightFlower,
	# fire a bubble, then continue to the MagicalTree.
	t.add(2, 0, 390, {"axis": 1.0})
	t.add(2, 391, 480, {"axis": 0.0})
	t.add(2, 117, 117, {"action": true})
	t.add(2, 119, 119, {"action": true})
	t.add(2, 121, 121, {"action": true})
	t.add(2, 123, 123, {"action": true})
	t.add(2, 125, 125, {"action": true})
	t.add(2, 127, 127, {"action": true})
	t.add(2, 129, 129, {"action": true})
	# Jump onto Platform6 (1800, 580) — jump early enough to clear the
	# platform's left edge from below before rising to its height.
	t.add(2, 200, 205, {"jump": true})
	t.add(2, 222, 222, {"action": true})
	t.add(2, 224, 224, {"action": true})
	t.add(2, 226, 226, {"action": true})
	# Jump over SeedGrove1 enemy (2380, 696) to avoid taking a 4th hit.
	t.add(2, 295, 300, {"jump": true})
	t.add(2, 265, 265, {"action": true})
	t.add(2, 267, 267, {"action": true})
	t.add(2, 269, 269, {"action": true})
	t.add(2, 281, 281, {"action": true})
	t.add(2, 283, 283, {"action": true})
	t.add(2, 285, 285, {"action": true})
	# Rabbit (peer 1): platform to OverheadSwitch, activate it, drop down and
	# walk right to activate LeftFlower, then continue to the MagicalTree.
	t.add(1, 0, 150, {"axis": 1.0})
	t.add(1, 151, 155, {"axis": 0.0})
	t.add(1, 156, 370, {"axis": 1.0})
	t.add(1, 371, 480, {"axis": 0.0})
	t.add(1, 5, 10, {"jump": true})
	t.add(1, 45, 50, {"jump": true})
	t.add(1, 115, 120, {"jump": true})
	t.add(1, 151, 151, {"action": true})
	t.add(1, 153, 153, {"action": true})
	t.add(1, 155, 155, {"action": true})
	t.add(1, 241, 241, {"action": true})
	t.add(1, 243, 243, {"action": true})
	t.add(1, 245, 245, {"action": true})
	t.capture(120, "fox_at_log")
	t.capture(160, "fallen_log_gate")
	t.capture(240, "bubble_pickup")
	t.capture(270, "bubble_grove_gate")
	t.capture(300, "bubble_fired")
	t.capture(400, "level_finish")
	t.assert_end("score_gt", [0])
	t.assert_end("finished")
	t.assert_end("no_errors")
	t.assert_end("both_alive")
	return t
