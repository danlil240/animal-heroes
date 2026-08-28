extends Control

## Asks before leaving a level, so an accidental tap never throws away progress.

signal resume_requested()
signal exit_requested()

@onready var resume_button: Button = $Panel/VBox/Resume
@onready var exit_button: Button = $Panel/VBox/Exit


func _ready() -> void:
	layout_direction = Control.LAYOUT_DIRECTION_RTL
	hide()
	resume_button.pressed.connect(_on_resume_pressed)
	exit_button.pressed.connect(_on_exit_pressed)


func open() -> void:
	show()


func close() -> void:
	hide()


func _on_resume_pressed() -> void:
	close()
	resume_requested.emit()


func _on_exit_pressed() -> void:
	close()
	exit_requested.emit()
