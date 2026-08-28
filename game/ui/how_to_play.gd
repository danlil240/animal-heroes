extends Control

signal back_requested()

const CYCLE_SECONDS := 1.8
const BASE_HERO_POSITION := Vector2(310.0, 78.0)

var _elapsed := 0.0

@onready var hero: ColorRect = $Demo/Hero
@onready var left_hint: PanelContainer = $Demo/Controls/Left
@onready var right_hint: PanelContainer = $Demo/Controls/Right
@onready var jump_hint: PanelContainer = $Demo/Controls/Jump
@onready var action_hint: PanelContainer = $Demo/Controls/Action
@onready var instruction: Label = $Instruction


func _ready() -> void:
	layout_direction = Control.LAYOUT_DIRECTION_RTL
	$Back.pressed.connect(func() -> void: back_requested.emit())


func _process(delta: float) -> void:
	advance_demo(delta)


func advance_demo(delta: float) -> void:
	_elapsed = fmod(_elapsed + delta, CYCLE_SECONDS)
	var phase := _elapsed / CYCLE_SECONDS
	var direction := sin(phase * TAU)
	hero.position = BASE_HERO_POSITION + Vector2(direction * 110.0, -maxf(0.0, sin(phase * TAU * 2.0)) * 44.0)
	_set_highlight(left_hint, direction < -0.25)
	_set_highlight(right_hint, direction > 0.25)
	_set_highlight(jump_hint, phase > 0.43 and phase < 0.68)
	_set_highlight(action_hint, phase > 0.72)
	if phase < 0.4:
		instruction.text = "זזים ימינה ושמאלה"
	elif phase < 0.7:
		instruction.text = "קופצים מעל מכשולים"
	else:
		instruction.text = "לוחצים פעולה ליד חברים וחפצים"


func _set_highlight(control: Control, active: bool) -> void:
	control.modulate = Color("fff19a") if active else Color.WHITE
