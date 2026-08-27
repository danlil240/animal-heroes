extends Control

signal create_game
signal join_game
signal open_competition

const COOP_MODE := "coop"
const COOP_LEVEL := "sunny_forest"
const COMPETITION_MODE := "competition"
const COMPETITION_LEVEL := "star_race"

@onready var choices: VBoxContainer = $Margin/VBox


func _ready() -> void:
	layout_direction = Control.LAYOUT_DIRECTION_RTL
	_show_home()


func _show_home() -> void:
	_clear_choices()
	_add_choice("Coop", "משחק משותף", _show_coop_choices)
	_add_choice("Competition", "תחרות", _open_competition)
	_add_choice("HowTo", "איך משחקים", _open_how_to)
	_add_choice("Settings", "הגדרות", _open_settings)


func _show_coop_choices() -> void:
	_clear_choices()
	_add_choice("Create", "יצירת משחק", _create_game)
	_add_choice("Join", "הצטרפות למשחק", _join_game)
	_add_choice("Back", "חזרה", _show_home)


func _clear_choices() -> void:
	for child in choices.get_children():
		choices.remove_child(child)
		child.queue_free()


func _add_choice(node_name: String, label: String, pressed_callback: Callable) -> void:
	var button := Button.new()
	button.name = node_name
	button.text = label
	button.layout_direction = Control.LAYOUT_DIRECTION_RTL
	button.custom_minimum_size = Vector2(0.0, 96.0)
	button.add_theme_font_size_override("font_size", 28)
	button.pressed.connect(pressed_callback)
	choices.add_child(button)


func _create_game() -> void:
	AppState.start_mode(COOP_MODE, COOP_LEVEL)
	create_game.emit()


func _join_game() -> void:
	AppState.start_mode(COOP_MODE, COOP_LEVEL)
	join_game.emit()


func _open_competition() -> void:
	AppState.start_mode(COMPETITION_MODE, COMPETITION_LEVEL)
	open_competition.emit()


func _open_how_to() -> void:
	AppState.start_mode("tutorial", "how_to_play")


func _open_settings() -> void:
	AppState.start_mode("settings", "")
