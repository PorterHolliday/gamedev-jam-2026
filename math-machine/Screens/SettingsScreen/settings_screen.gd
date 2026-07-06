class_name SettingsScreen
extends Control

@onready var back_button: Button = %BackButton
@onready var music_slider: HSlider = %MusicSlider
@onready var music_percentage: Label = %MusicPercentage
@onready var sfx_slider: HSlider = %SFXSlider
@onready var sfx_percentage: Label = %SFXPercentage
@onready var settings_data: SettingsData

func _ready() -> void:
	_init_settings()
	back_button.pressed.connect(_on_back_button_pressed)
	music_slider.value_changed.connect(_on_music_slider_value_changed)
	music_slider.drag_ended.connect(_on_slider_drag_ended)
	sfx_slider.value_changed.connect(_on_sfx_slider_value_changed)
	sfx_slider.drag_ended.connect(_on_slider_drag_ended)
	
func _init_settings() -> void:
	_load_settings_data()
	music_slider.value = settings_data.music_volume
	sfx_slider.value = settings_data.sfx_volume
	music_percentage.text = str(int(music_slider.value)) + '%'
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index('Music'), linear_to_db(music_slider.value / 100))
	sfx_percentage.text = str(int(sfx_slider.value)) + '%'
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index('SFX'), linear_to_db(sfx_slider.value / 100))
	
func _load_settings_data() -> void:
	if FileAccess.file_exists("res://Screens/SettingsScreen/SettingsData/settings_data.tres"):
		settings_data = load("res://Screens/SettingsScreen/SettingsData/settings_data.tres")
		return
		
	var default_settings_data: SettingsData = load("res://Screens/SettingsScreen/SettingsData/default_settings_data.tres")
	settings_data = default_settings_data.duplicate()
	settings_data.resource_path = default_settings_data.resource_path.replace('default_', '')
	
func _on_back_button_pressed() -> void:
	GameRoot.exit_settings_screen()
	
func _on_music_slider_value_changed(value: float) -> void:
	music_percentage.text = str(int(value)) + '%'
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index('Music'), linear_to_db(value / 100))
	settings_data.music_volume = value
	
func _on_sfx_slider_value_changed(value: float) -> void:
	sfx_percentage.text = str(int(value)) + '%'
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index('SFX'), linear_to_db(value / 100))
	settings_data.sfx_volume = value

func _on_slider_drag_ended(value_changed: bool) -> void:
	if not value_changed: return
	settings_data.save()
