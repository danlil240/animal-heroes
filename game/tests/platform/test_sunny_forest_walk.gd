extends "res://tests/platform/test_runner.gd"


func _build_timeline() -> InputTimeline:
	var t := InputTimeline.new(300)
	t.add(1, 0, 180, {"axis": 1.0})
	t.add(1, 30, 35, {"axis": 1.0, "jump": true})
	t.add(1, 60, 65, {"axis": 1.0, "jump": true})
	t.add(2, 0, 200, {"axis": 1.0})
	t.add(2, 45, 50, {"axis": 1.0, "jump": true})
	t.capture(60, "meadow_start")
	t.capture(150, "meadow_mid")
	t.capture(250, "meadow_end")
	t.assert_at(250, "position_gt", [1, "x", 400])
	t.assert_at(250, "position_gt", [2, "x", 300])
	t.assert_end("no_errors")
	t.assert_end("both_alive")
	return t
