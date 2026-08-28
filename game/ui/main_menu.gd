extends Control

## Hebrew home menu.
##
## The menu decides nothing about scenes: it records the choice on AppState and
## reports whether this tablet wants to host or join, then GameShell opens the
## matching screen. Only the cooperative panel and its back path replace the
## choice column, so the column never grows past the tablet screen.

signal create_game
signal join_game
signal open_competition

const COOP_LEVEL := "sunny_forest"
const COMPETITION_LEVEL := "star_race"
const TARGET_SIZE := Vector2(96.0, 96.0)

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
	AppState.select_mode(AppState.MODE_COOP, COOP_LEVEL)
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
	button.custom_minimum_size = TARGET_SIZE
	button.add_theme_font_size_override("font_size", 28)
	button.pressed.connect(pressed_callback)
	choices.add_child(button)


func _create_game() -> void:
	AppState.select_mode(AppState.MODE_COOP, COOP_LEVEL)
	create_game.emit()


func _join_game() -> void:
	AppState.select_mode(AppState.MODE_COOP, COOP_LEVEL)
	join_game.emit()


func _open_competition() -> void:
	AppState.select_mode(AppState.MODE_COMPETITION, COMPETITION_LEVEL)
	open_competition.emit()


func _open_how_to() -> void:
	AppState.start_mode(AppState.MODE_TUTORIAL, AppState.TUTORIAL_ID)


func _open_settings() -> void:
	AppState.start_mode(AppState.MODE_SETTINGS, AppState.SETTINGS_ID)
