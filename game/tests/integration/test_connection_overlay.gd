extends SceneTree


func _init() -> void:
	var scene = load("res://ui/connection_overlay.tscn")
	if scene == null:
		_fail("connection overlay scene must exist")
		return
	var overlay = scene.instantiate()
	root.add_child(overlay)
	var expectations := {
		"discovering": "מחפש משחק…",
		"connecting": "מתחבר…",
		"lobby": "מחכים לשחקן נוסף",
		"playing": "מתחילים!",
	}
	for state in expectations:
		overlay.show_state(state)
		if overlay.get_node("Panel/Status").text != expectations[state]:
			_fail("overlay message missing for %s" % state)
			return
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
