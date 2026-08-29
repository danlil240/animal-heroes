extends "res://tests/platform/test_runner.gd"


func _build_timeline() -> InputTimeline:
	var t := InputTimeline.new(170)
	# Fox (peer 2): walk right to FallenLog (x≈1110) and push it.
	# FallenLog requires fox (can_push_heavy=true).
	t.add(2, 0, 135, {"axis": 1.0})
	t.add(2, 117, 117, {"action": true})
	t.add(2, 119, 119, {"action": true})
	t.add(2, 121, 121, {"action": true})
	t.add(2, 123, 123, {"action": true})
	t.add(2, 125, 125, {"action": true})
	t.add(2, 127, 127, {"action": true})
	t.add(2, 129, 129, {"action": true})
	# Rabbit (peer 1): platform up to OverheadSwitch (x≈1370, y≈440).
	# OverheadSwitch requires rabbit.
	t.add(1, 0, 150, {"axis": 1.0})
	t.add(1, 151, 170, {"axis": 0.0})
	t.add(1, 5, 10, {"jump": true})
	t.add(1, 45, 50, {"jump": true})
	t.add(1, 115, 120, {"jump": true})
	t.add(1, 151, 151, {"action": true})
	t.add(1, 153, 153, {"action": true})
	t.add(1, 155, 155, {"action": true})
	t.add(1, 157, 157, {"action": true})
	t.add(1, 159, 159, {"action": true})
	t.capture(50, "rabbit_on_p1")
	t.capture(120, "fox_at_log")
	t.capture(160, "gate_opened")
	t.assert_end("gate_open", ["fallen-log"])
	t.assert_end("not_finished")
	t.assert_end("no_errors")
	t.assert_end("both_alive")
	return t
