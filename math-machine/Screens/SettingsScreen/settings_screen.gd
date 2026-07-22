class_name SettingsScreen
extends Control

@onready var back_button: Button = %BackButton
@onready var music_slider: HSlider = %MusicSlider
@onready var music_percentage: Label = %MusicPercentage
@onready var sfx_slider: HSlider = %SFXSlider
@onready var sfx_percentage: Label = %SFXPercentage

func _ready() -> void:
	_init_settings()
	back_button.pressed.connect(_on_back_button_pressed)
	music_slider.value_changed.connect(_on_music_slider_value_changed)
	music_slider.drag_ended.connect(_on_slider_drag_ended)
	sfx_slider.value_changed.connect(_on_sfx_slider_value_changed)
	sfx_slider.drag_ended.connect(_on_slider_drag_ended)
	
func _init_settings() -> void:
	if not SaveManager.is_node_ready():
		await SaveManager.ready
	music_slider.value = SaveManager.music_volume
	sfx_slider.value = SaveManager.sfx_volume
	music_percentage.text = str(int(music_slider.value)) + '%'
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index('Music'), linear_to_db(music_slider.value / 100))
	sfx_percentage.text = str(int(sfx_slider.value)) + '%'
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index('SFX'), linear_to_db(sfx_slider.value / 100))
	
func _on_back_button_pressed() -> void:
	AudioManager.play_button_click_sfx()
	GameRoot.exit_settings_screen()
	
func _on_music_slider_value_changed(value: float) -> void:
	music_percentage.text = str(int(value)) + '%'
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index('Music'), linear_to_db(value / 100))
	SaveManager.music_volume = value
	
func _on_sfx_slider_value_changed(value: float) -> void:
	sfx_percentage.text = str(int(value)) + '%'
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index('SFX'), linear_to_db(value / 100))
	SaveManager.sfx_volume = value

func _on_slider_drag_ended(value_changed: bool) -> void:
	if not value_changed: return
	SaveManager.save_game()
