extends Control

signal rematch_requested
signal next_level_requested
signal return_to_menu

var displayed_scores: Dictionary = {}
var displayed_team_score: int = 0
var displayed_stars: int = 0
var winner_peer_id: int = 0
var _rematch_choices: Dictionary = {}


@onready var title: Label = $Margin/VBox/Title
@onready var scores_container: VBoxContainer = $Margin/VBox/Scores
@onready var next_button: Button = $Margin/VBox/Next
@onready var rematch_button: Button = $Margin/VBox/Rematch
@onready var menu_button: Button = $Margin/VBox/Menu


func _ready() -> void:
	layout_direction = Control.LAYOUT_DIRECTION_RTL
	rematch_button.text = "שוב!"
	menu_button.text = "בחירת משחק"
	next_button.pressed.connect(_on_next_pressed)
	rematch_button.pressed.connect(_on_rematch_pressed)
	menu_button.pressed.connect(_on_menu_pressed)
	_clear_scores()


func show_result(result) -> void:
	reset()
	if result == null:
		return
	winner_peer_id = int(result.get("winner_peer_id", 0))
	displayed_scores = result.get("scores", {}).duplicate()
	displayed_team_score = int(result.get("team_score", 0))
	displayed_stars = int(result.get("stars_collected", 0))
	title.text = "כל הכבוד!"
	_show_next_level(String(result.get("next_level_id", "")))
	_populate_scores()


func choose_rematch(peer_id: int) -> void:
	_rematch_choices[peer_id] = true


func cancel_rematch(peer_id: int) -> void:
	_rematch_choices.erase(peer_id)


func rematch_ready() -> bool:
	return _rematch_choices.size() >= 2


func reset() -> void:
	displayed_scores.clear()
	displayed_team_score = 0
	displayed_stars = 0
	winner_peer_id = 0
	_rematch_choices.clear()
	_show_next_level("")
	_clear_scores()


## Offers the next campaign level only when the finished level has one.
func _show_next_level(next_level_id: String) -> void:
	next_button.visible = not next_level_id.is_empty()
	if next_button.visible:
		next_button.text = "ממשיכים ל%s" % AppState.title_for(next_level_id)


func _populate_scores() -> void:
	_clear_scores()
	if displayed_scores.is_empty() and (displayed_team_score > 0 or displayed_stars > 0):
		_add_result_label("ניקוד קבוצתי: %d" % displayed_team_score, Color(1, 0.84, 0.22))
		_add_result_label("כוכבים: %d" % displayed_stars, Color(0.86, 0.96, 1.0))
		return
	var peer_ids: Array = displayed_scores.keys()
	peer_ids.sort()
	for peer_id in peer_ids:
		_add_result_label(
			"שחקן %d: %d" % [int(peer_id), int(displayed_scores[peer_id])],
			Color(1, 0.84, 0) if int(peer_id) == winner_peer_id else Color.WHITE,
		)


func _add_result_label(text_value: String, color: Color) -> void:
	var label := Label.new()
	label.text = text_value
	label.layout_direction = Control.LAYOUT_DIRECTION_RTL
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 36)
	label.add_theme_color_override("font_color", color)
	scores_container.add_child(label)


func _clear_scores() -> void:
	for child in scores_container.get_children():
		scores_container.remove_child(child)
		child.queue_free()


func _on_next_pressed() -> void:
	next_level_requested.emit()


func _on_rematch_pressed() -> void:
	rematch_requested.emit()


func _on_menu_pressed() -> void:
	return_to_menu.emit()
