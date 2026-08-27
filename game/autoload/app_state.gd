extends Node

var selected_mode := ""
var selected_level := ""

func start_mode(mode_id: String, level_id: String) -> void:
	selected_mode = mode_id
	selected_level = level_id
