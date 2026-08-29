extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if not await _test_bubble_bounce_hud():
		return
	if not await _test_star_race_hud():
		return
	quit(0)


func _test_star_race_hud() -> bool:
	var scene: PackedScene = load("res://ui/star_race_hud.tscn")
	if scene == null:
		return _fail_bool("star race HUD scene must load")
	var hud = scene.instantiate()
	root.add_child(hud)
	await process_frame
	hud.render(2, 4, false, true)
	if hud.get_node("HostProgress").text != "2/4":
		return _fail_bool("star race HUD host progress must read N/4, got %s" % hud.get_node("HostProgress").text)
	if hud.get_node("GuestProgress").text != "4/4 ✓":
		return _fail_bool("star race HUD must append checkmark when finished, got %s" % hud.get_node("GuestProgress").text)
	hud.render(4, 4, true, true)
	if hud.get_node("HostProgress").text != "4/4 ✓":
		return _fail_bool("star race HUD host must show checkmark when finished, got %s" % hud.get_node("HostProgress").text)
	hud.queue_free()
	return true


func _test_bubble_bounce_hud() -> bool:
	var scene: PackedScene = load("res://ui/bubble_bounce_hud.tscn")
	if scene == null:
		return _fail_bool("bubble bounce HUD scene must load")
	var hud = scene.instantiate()
	root.add_child(hud)
	await process_frame
	hud.render(180.0, 3, 1, 2)
	if hud.get_node("Timer").text != "3:00":
		return _fail_bool("bubble bounce HUD timer must format M:SS, got %s" % hud.get_node("Timer").text)
	if hud.get_node("HostScore").text != "3":
		return _fail_bool("bubble bounce HUD must show host score")
	if hud.get_node("GuestScore").text != "1":
		return _fail_bool("bubble bounce HUD must show guest score")
	var marks: Array[Node] = hud.get_node("Ammo/Marks").get_children()
	if marks.size() != 5:
		return _fail_bool("bubble bounce HUD must precreate five ammo marks")
	for index in marks.size():
		if marks[index].visible != (index < 2):
			return _fail_bool("bubble bounce HUD ammo marks must match local ammo")
	hud.render(7.0, 0, 0, 0)
	if hud.get_node("Timer").text != "0:07":
		return _fail_bool("bubble bounce HUD timer must show seconds under ten, got %s" % hud.get_node("Timer").text)
	if hud.get_node("Ammo").visible:
		return _fail_bool("bubble bounce HUD ammo must hide when empty")
	hud.queue_free()
	return true


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _fail_bool(message: String) -> bool:
	_fail(message)
	return false
