class_name LevelCompletePopup
extends Control

const MUSIC_FADE_DURATION: float = 0.7

@onready var next_level_button: Button = %NextLevelButton
@onready var level_select_button: Button = %LevelSelectButton
@onready var animation_player: AnimationPlayer = %AnimationPlayer

var current_music_volume: float = 1.0

func _ready() -> void:
	next_level_button.pressed.connect(_on_next_level_button_pressed)
	level_select_button.pressed.connect(_on_level_select_button_pressed)
	animation_player.play('level_complete')
	current_music_volume = AudioServer.get_bus_volume_linear(AudioServer.get_bus_index('Music'))
	_fade_down_music()
	
func play_level_complete_sfx() -> void:
	AudioManager.play_level_complete_sfx()
	
func _on_next_level_button_pressed() -> void:
	GameRoot.enter_next_level()
	_fade_up_music()
	queue_free()
	
func _on_level_select_button_pressed() -> void:
	GameRoot.enter_level_select_screen()
	_fade_up_music()
	queue_free()
	
func _fade_down_music() -> void:
	var tween = get_tree().create_tween()
	tween.tween_method(
		func(volume):
			AudioServer.set_bus_volume_linear(AudioServer.get_bus_index('Music'), volume),
		current_music_volume, current_music_volume / 2.0, MUSIC_FADE_DURATION)

func _fade_up_music() -> void:
	var tween = get_tree().create_tween()
	tween.tween_method(
		func(volume):
			AudioServer.set_bus_volume_linear(AudioServer.get_bus_index('Music'), volume),
		current_music_volume / 2.0, current_music_volume, MUSIC_FADE_DURATION)
