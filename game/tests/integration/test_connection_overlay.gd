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
	if not overlay.has_method("show_incompatibility"):
		_fail("overlay must show local compatibility messages")
		return
	var incompatibility_messages := {
		"local_older": "צריך לעדכן את הטאבלט הזה לפני המשחק",
		"remote_older": "צריך לעדכן את הטאבלט השני לפני המשחק",
		"unknown": "גרסאות המשחק אינן תואמות. עדכנו את שני הטאבלטים",
		"same": "גרסאות המשחק אינן תואמות. עדכנו את שני הטאבלטים",
	}
	for relation in incompatibility_messages:
		overlay.show_incompatibility(relation)
		if overlay.get_node("Panel/Status").text != incompatibility_messages[relation] or not overlay.visible:
			_fail("overlay must map %s locally" % relation)
			return
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
