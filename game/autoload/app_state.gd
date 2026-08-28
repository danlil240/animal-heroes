extends Node

## Navigation and progression state for the whole app.
##
## AppState records what should be on screen and what the campaign has
## unlocked; GameShell owns the single place where scenes are actually swapped.
## Keeping the two apart lets every screen and level be exercised in tests
## without driving real scene transitions.

## A screen or level was chosen and should be opened now.
signal mode_started(mode_id: String, level_id: String)
## A level or match ended and its result should be shown.
signal results_requested(result: Dictionary)
## The player asked to go back to the main menu.
signal menu_requested()

const MODE_COOP := "coop"
const MODE_COMPETITION := "competition"
const MODE_TUTORIAL := "tutorial"
const MODE_SETTINGS := "settings"

const MENU_SCENE := "res://ui/main_menu.tscn"
const RESULTS_SCENE := "res://ui/results_screen.tscn"

const TUTORIAL_ID := "how_to_play"
const SETTINGS_ID := "settings"

const CAMPAIGN_ORDER: Array[String] = ["sunny_forest", "crystal_caves", "cloud_factory", "robot_boss"]
const COMPETITION_ORDER: Array[String] = ["star_race", "treasure_dash", "bubble_bounce"]

const SCENES := {
	"sunny_forest": "res://levels/sunny_forest.tscn",
	"crystal_caves": "res://levels/crystal_caves.tscn",
	"cloud_factory": "res://levels/cloud_factory.tscn",
	"robot_boss": "res://levels/robot_boss.tscn",
	"star_race": "res://levels/star_race_arena.tscn",
	"treasure_dash": "res://levels/treasure_dash_arena.tscn",
	"bubble_bounce": "res://levels/bubble_bounce_arena.tscn",
	"test_arena": "res://levels/test_arena.tscn",
	TUTORIAL_ID: "res://ui/how_to_play.tscn",
	SETTINGS_ID: "res://ui/settings_screen.tscn",
}

const TITLES := {
	"sunny_forest": "יער השמש",
	"crystal_caves": "מערות הגביש",
	"cloud_factory": "מפעל העננים",
	"robot_boss": "הרובוט הענק",
	"star_race": "מרוץ הכוכבים",
	"treasure_dash": "מצוד האוצרות",
	"bubble_bounce": "קרב הבועות",
}

## Autoload scripts are compiled before the other singletons are registered, so
## the save store is resolved on the tree rather than by its global name.
const SaveStoreScript := preload("res://autoload/save_store.gd")

var selected_mode := ""
var selected_level := ""
var last_result: Dictionary = {}

var _save_store: Node = null


## Records a choice without opening it yet, for menus that still have a
## submenu to show.
func select_mode(mode_id: String, level_id: String) -> void:
	selected_mode = mode_id
	selected_level = level_id


## Records a choice and asks the shell to open it.
func start_mode(mode_id: String, level_id: String) -> void:
	select_mode(mode_id, level_id)
	mode_started.emit(mode_id, level_id)


func open_results(result: Dictionary) -> void:
	last_result = result.duplicate(true)
	results_requested.emit(last_result)


func return_to_menu() -> void:
	menu_requested.emit()


func scene_path_for(level_id: String) -> String:
	return SCENES.get(level_id, "")


func title_for(level_id: String) -> String:
	return TITLES.get(level_id, "")


func is_campaign_level(level_id: String) -> bool:
	return CAMPAIGN_ORDER.has(level_id)


func next_campaign_level(level_id: String) -> String:
	var index: int = CAMPAIGN_ORDER.find(level_id)
	if index < 0 or index + 1 >= CAMPAIGN_ORDER.size():
		return ""
	return CAMPAIGN_ORDER[index + 1]


## Campaign levels the players have reached; the first level is always open.
func unlocked_levels() -> Array:
	var stored: Variant = save_store().load_data().get("unlocked_levels", [])
	var levels: Array = []
	for level in CAMPAIGN_ORDER:
		if stored is Array and (stored as Array).has(level):
			levels.append(level)
	if levels.is_empty():
		levels.append(CAMPAIGN_ORDER[0])
	return levels


func is_unlocked(level_id: String) -> bool:
	if not is_campaign_level(level_id):
		return SCENES.has(level_id)
	return unlocked_levels().has(level_id)


func unlock_levels(levels: Array) -> void:
	var data: Dictionary = save_store().load_data()
	var stored: Variant = data.get("unlocked_levels", [])
	var unlocked: Array = stored.duplicate() if stored is Array else []
	var added := false
	for level in levels:
		if is_campaign_level(level) and not unlocked.has(level):
			unlocked.append(level)
			added = true
	if not added:
		return
	data["unlocked_levels"] = unlocked
	save_store().save_data(data)


## Records the progress a finished level reported, so the next level opens.
func record_result(result: Dictionary) -> void:
	var unlocked: Variant = result.get("unlocked_levels", [])
	if unlocked is Array:
		unlock_levels(unlocked)
	var next_level_id := String(result.get("next_level_id", ""))
	if not next_level_id.is_empty():
		unlock_levels([next_level_id])
	if bool(result.get("campaign_completed", false)):
		unlock_levels(CAMPAIGN_ORDER)


## The shared save store, or a private one when running without autoloads.
func save_store() -> Node:
	if _save_store == null:
		_save_store = get_node_or_null("/root/SaveStore")
	if _save_store == null:
		_save_store = SaveStoreScript.new()
		_save_store.name = "FallbackSaveStore"
		add_child(_save_store)
	return _save_store
