extends Control

@onready var play_button: Button = %PlayButton
@onready var settings_button: Button = %SettingsButton
@onready var credits_button: Button = %CreditsButton
@onready var button_audio: AudioStreamPlayer = %ButtonAudio

func _ready() -> void:
	play_button.pressed.connect(_on_play_button_pressed)
	settings_button.pressed.connect(_on_settings_button_pressed)
	credits_button.pressed.connect(_on_credits_button_pressed)
	
func _on_play_button_pressed() -> void:
	AudioManager.play_button_click_sfx()
	GameRoot.enter_level_select_screen()

func _on_settings_button_pressed() -> void:
	AudioManager.play_button_click_sfx()
	GameRoot.enter_settings_screen()
	
func _on_credits_button_pressed() -> void:
	AudioManager.play_button_click_sfx()
	GameRoot.enter_credits_screen()
