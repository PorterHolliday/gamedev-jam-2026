extends Control

@onready var level_buttons_container: Node = %LevelButtonsContainer
@onready var back_button: Button = %BackButton
@onready var settings_button: Button = %SettingsButton
@onready var button_audio: AudioStreamPlayer = %ButtonAudio

var level_buttons: Array[LevelButton] = [null]

func _ready() -> void:
	back_button.pressed.connect(_on_back_button_pressed)
	settings_button.pressed.connect(_on_settings_button_pressed)
	_init_level_buttons()
	
func _init_level_buttons() -> void:
	var level_number: int = 0
	var previous_level_complete = false
	for child in level_buttons_container.get_children():
		if child is LevelButton:
			child.pressed.connect(func():
				_on_level_button_pressed(child))
			child.level_number = level_number
			if previous_level_complete:
				child.disabled = false
			if level_number < LevelManager.level_scenes.size() and LevelManager.levels_completed[level_number]:
				child.level_complete = true
				previous_level_complete = true
			else:
				previous_level_complete = false
			level_buttons.append(child)
			level_number += 1
			
func _on_level_button_pressed(button: LevelButton) -> void:
	var level_scene: PackedScene = LevelManager.get_level_scene(button.level_number)
	GameRoot.enter_level(level_scene)
	
func _on_level_back_button_pressed() -> void:
	GameRoot.enter_level_select_screen()
	
func _on_level_restarted() -> void:
	GameRoot.enter_level(LevelManager.get_current_level_scene())
	
func _on_level_completed() -> void:
	GameRoot.level_complete()
	
func _play_button_audio() -> void:
	button_audio.volume_db = randf_range(-5, 0)
	button_audio.pitch_scale = randf_range(0.8, 1.2)
	button_audio.play(0.17)
		
func _on_back_button_pressed() -> void:
	_play_button_audio()
	GameRoot.enter_title_screen()
	
func _on_settings_button_pressed() -> void:
	_play_button_audio()
	GameRoot.enter_settings_screen()
	
#func _music_fade_in() -> void:
	#level_selection_music.play()
	#var prev_db = level_selection_music.volume_db
	#level_selection_music.volume_db = prev_db - 10
	#var tween = get_tree().create_tween()
	#tween.tween_property(level_selection_music, 'volume_db', prev_db, 2)
