extends SceneTree

const InputTimelineScript := preload("res://tests/platform/input_timeline.gd")

func _init() -> void:
	var failures := 0
	var t := InputTimelineScript.new(300)
	if t.total_frames() != 300:
		push_error("total_frames should honor hint"); failures += 1
	t.add(1, 0, 180, {"axis": 1.0})
	var f := t.frame_for(1, 50)
	if f.axis != 1.0 or f.jump or f.action:
		push_error("frame_for single range failed"); failures += 1
	var f0 := t.frame_for(1, 200)
	if f0.axis != 0.0:
		push_error("frame_for outside range should be neutral"); failures += 1
	t.add(1, 30, 35, {"axis": 1.1, "jump": true})
	var fj := t.frame_for(1, 32)
	if fj.axis != 1.1 or not fj.jump:
		push_error("overlapping ranges should merge (latest axis + OR jump)"); failures += 1
	t.add(2, 0, 200, {"axis": 1.0})
	if t.frame_for(2, 100).axis != 1.0:
		push_error("peer 2 independent input failed"); failures += 1
	if t.frame_for(1, 100).jump:
		push_error("peer 1 jump should not persist outside burst"); failures += 1
	t.capture(60, "meadow_start")
	t.capture(150, "meadow_mid")
	var caps := t.captures()
	if caps.size() != 2 or caps[0].frame != 60 or caps[0].name != "meadow_start":
		push_error("captures not recorded correctly"); failures += 1
	t.assert_at(250, "position_gt", [1, "x", 400])
	t.assert_end("no_errors")
	var asserts := t.assertions()
	if asserts.size() != 2:
		push_error("assertions not recorded"); failures += 1
	if asserts[0].kind != "position_gt" or asserts[0].frame != 250:
		push_error("assert_at not recorded correctly"); failures += 1
	if asserts[1].kind != "no_errors" or asserts[1].has("frame"):
		push_error("assert_end should have no frame key"); failures += 1
	var t2 := InputTimelineScript.new(10)
	t2.capture(50, "late")
	if t2.total_frames() != 50:
		push_error("total_frames should grow to last capture"); failures += 1
	if failures == 0:
		print("VISUAL_TEST_RESULT name=input_timeline_unit status=pass")
		quit(0)
	else:
		print("VISUAL_TEST_RESULT name=input_timeline_unit status=fail")
		quit(1)
