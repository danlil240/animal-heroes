extends Control

## Hebrew parent modal for checking and requesting tablet updates.
##
## Opened by a deliberate hold gesture (not a tap). Shows installed and
## available version state, PC availability, and paired status. Disables
## the update action during gameplay, offline/unpaired states, unavailable
## devices, or an active update. Never downloads or installs APK bytes
## and never requests package-installer permissions.

signal update_both_requested()

const HOLD_SECONDS := 1.5

@onready var status_label: Label = $Panel/VBox/Status
@onready var installed_label: Label = $Panel/VBox/InstalledVersion
@onready var available_label: Label = $Panel/VBox/AvailableVersion
@onready var pc_label: Label = $Panel/VBox/PcStatus
@onready var paired_label: Label = $Panel/VBox/PairedStatus
@onready var update_button: Button = $Panel/VBox/UpdateBoth
@onready var close_button: Button = $Panel/VBox/Close

var _hold_timer := 0.0
var _is_holding := false
var _update_in_progress := false
var _pc_available := false
var _is_paired := false
var _installed_version_name := ""
var _installed_version_code := 0
var _available_version_name := ""
var _available_version_code := 0


func _ready() -> void:
	layout_direction = Control.LAYOUT_DIRECTION_RTL
	hide()
	update_button.pressed.connect(_on_update_pressed)
	close_button.pressed.connect(close)
	update_button.disabled = true


func _process(delta: float) -> void:
	if _is_holding:
		_hold_timer += delta
		if _hold_timer >= HOLD_SECONDS:
			_is_holding = false
			open()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_is_holding = true
			_hold_timer = 0.0
		else:
			_is_holding = false
			_hold_timer = 0.0


func open() -> void:
	show()
	_refresh_state()


func close() -> void:
	hide()


func set_installed_version(version_name: String, version_code: int) -> void:
	_installed_version_name = version_name
	_installed_version_code = version_code
	_refresh_state()


func set_available_version(version_name: String, version_code: int) -> void:
	_available_version_name = version_name
	_available_version_code = version_code
	_refresh_state()


func set_pc_available(available: bool) -> void:
	_pc_available = available
	_refresh_state()


func set_paired(paired: bool) -> void:
	_is_paired = paired
	_refresh_state()


func set_update_in_progress(in_progress: bool) -> void:
	_update_in_progress = in_progress
	_refresh_state()


func is_update_allowed() -> bool:
	if _update_in_progress:
		return false
	if not _pc_available:
		return false
	if not _is_paired:
		return false
	if _available_version_code <= _installed_version_code:
		return false
	return true


func status_text() -> String:
	if _update_in_progress:
		return "מעדכן…"
	if not _pc_available:
		return "המחשב אינו זמין"
	if not _is_paired:
		return "הטאבלט אינו מצורף"
	if _available_version_code > _installed_version_code:
		return "עדכון זמין"
	return "הטאבלטים מעודכנים"


func _refresh_state() -> void:
	if not is_inside_tree():
		return
	installed_label.text = "גרסה מותקנת: %s" % _installed_version_name if _installed_version_name != "" else "גרסה מותקנת: לא ידוע"
	available_label.text = "גרסה זמינה: %s" % _available_version_name if _available_version_name != "" else "גרסה זמינה: לא ידוע"
	pc_label.text = "המחשב: מחובר" if _pc_available else "המחשב: לא מחובר"
	paired_label.text = "מצורף: כן" if _is_paired else "מצורף: לא"
	status_label.text = status_text()
	update_button.disabled = not is_update_allowed()


func _on_update_pressed() -> void:
	if not is_update_allowed():
		return
	update_button.disabled = true
	_update_in_progress = true
	_refresh_state()
	update_both_requested.emit()
