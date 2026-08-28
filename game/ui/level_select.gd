extends Control

## Picks the level or arena the hosting tablet will open, or hands over to the
## joining flow for a child who tapped the wrong button.

signal level_chosen(level_id: String)
signal join_requested()
signal back_requested()

const TARGET_SIZE := Vector2(96.0, 96.0)

@onready var title: Label = $Margin/VBox/Title
@onready var levels: GridContainer = $Margin/VBox/Levels
@onready var join_button: Button = $Margin/VBox/Join
@onready var back_button: Button = $Margin/VBox/Back


func _ready() -> void:
	layout_direction = Control.LAYOUT_DIRECTION_RTL
	join_button.pressed.connect(func() -> void: join_requested.emit())
	back_button.pressed.connect(func() -> void: back_requested.emit())


## Fills the picker with the given level ids, newest progress last.
func show_levels(level_ids: Array, heading: String) -> void:
	title.text = heading
	for child in levels.get_children():
		levels.remove_child(child)
		child.queue_free()
	for level_id in level_ids:
		var id := String(level_id)
		var button := Button.new()
		button.name = id
		button.text = AppState.title_for(id)
		button.layout_direction = Control.LAYOUT_DIRECTION_RTL
		button.custom_minimum_size = TARGET_SIZE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 26)
		button.pressed.connect(func() -> void: level_chosen.emit(id))
		levels.add_child(button)


func level_count() -> int:
	return levels.get_child_count()
