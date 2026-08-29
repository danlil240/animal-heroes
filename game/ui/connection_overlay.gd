extends Control


const STATE_MESSAGES := {
	"discovering": "מחפש משחק…",
	"connecting": "מתחבר…",
	"lobby": "מחכים לשחקן נוסף",
	"playing": "מתחילים!",
}

const INCOMPATIBILITY_MESSAGES := {
	"local_older": "צריך לעדכן את הטאבלט הזה לפני המשחק",
	"remote_older": "צריך לעדכן את הטאבלט השני לפני המשחק",
	"unknown": "גרסאות המשחק אינן תואמות. עדכנו את שני הטאבלטים",
	"same": "גרסאות המשחק אינן תואמות. עדכנו את שני הטאבלטים",
}


func _ready() -> void:
	var session = get_node_or_null("/root/Session")
	if session != null:
		session.state_changed.connect(show_state)
		show_state(session.state)


func show_state(state: String) -> void:
	get_node("Panel/Status").text = STATE_MESSAGES.get(state, "")
	# "playing" and "idle" both hide the overlay — gameplay has started
	# (or no session is active). Only connection-phase states show it.
	visible = state != "idle" and state != "playing"
	if state != "discovering":
		get_node("Panel/ManualIp").visible = false


func show_discovery_timeout() -> void:
	get_node("Panel/ManualIp").visible = true


func show_incompatibility(relation: String) -> void:
	get_node("Panel/Status").text = INCOMPATIBILITY_MESSAGES.get(relation, INCOMPATIBILITY_MESSAGES["unknown"])
	get_node("Panel/ManualIp").visible = false
	visible = true
