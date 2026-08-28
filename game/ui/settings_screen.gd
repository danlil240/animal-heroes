extends Control

## Hebrew settings: music volume, sound volume, and vibration.
##
## Every change is applied to the audio buses immediately and persisted through
## SaveStore, so a child never has to confirm anything.

signal back_requested()

const MUSIC_KEY := "music"
const SFX_KEY := "sfx"
const VIBRATION_KEY := "vibration"

@onready var music_slider: HSlider = $Margin/VBox/Music/Slider
@onready var music_value: Label = $Margin/VBox/Music/Value
@onready var sfx_slider: HSlider = $Margin/VBox/Sfx/Slider
@onready var sfx_value: Label = $Margin/VBox/Sfx/Value
@onready var vibration_button: Button = $Margin/VBox/Vibration
@onready var back_button: Button = $Margin/VBox/Back

var _settings: Dictionary = {}


func _ready() -> void:
	layout_direction = Control.LAYOUT_DIRECTION_RTL
	_settings = SaveStore.load_data()
	music_slider.value = float(_settings.get(MUSIC_KEY, 0.8))
	sfx_slider.value = float(_settings.get(SFX_KEY, 0.8))
	_refresh_labels()
	music_slider.value_changed.connect(_on_music_changed)
	sfx_slider.value_changed.connect(_on_sfx_changed)
	vibration_button.pressed.connect(_on_vibration_pressed)
	back_button.pressed.connect(func() -> void: back_requested.emit())


func settings() -> Dictionary:
	return _settings.duplicate(true)


func _on_music_changed(value: float) -> void:
	_store(MUSIC_KEY, value)


func _on_sfx_changed(value: float) -> void:
	_store(SFX_KEY, value)
	AudioDirector.play_ui_sound()


func _on_vibration_pressed() -> void:
	_store(VIBRATION_KEY, not bool(_settings.get(VIBRATION_KEY, true)))


func _store(key: String, value: Variant) -> void:
	_settings[key] = value
	SaveStore.save_data(_settings)
	AudioDirector.apply_settings(_settings)
	_refresh_labels()


func _refresh_labels() -> void:
	music_value.text = _percent(float(_settings.get(MUSIC_KEY, 0.8)))
	sfx_value.text = _percent(float(_settings.get(SFX_KEY, 0.8)))
	var vibration_on := bool(_settings.get(VIBRATION_KEY, true))
	vibration_button.text = "רעידות: פועל" if vibration_on else "רעידות: כבוי"


func _percent(value: float) -> String:
	return "%d%%" % int(round(clampf(value, 0.0, 1.0) * 100.0))
