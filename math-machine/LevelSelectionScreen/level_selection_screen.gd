extends Control

signal game_completed

#@onready var level_complete_popup: LevelCompletePopup = %LevelCompletePopup
@onready var back_button: Button = %BackButton
#@onready var animation_player: AnimationPlayer = %AnimationPlayer
@onready var button_audio: AudioStreamPlayer = %ButtonAudio
#@onready var level_complete_click_audio: AudioStreamPlayer = %LevelCompleteClickAudio
#@onready var level_selection_music: AudioStreamPlayer = $LevelSelectionMusic

var level_buttons: Array[LevelButton] = [null]
var current_level_button: LevelButton
var current_level: Node
var current_level_number: int = 0

func _ready() -> void:
	back_button.pressed.connect(_on_back_button_pressed)
	#level_complete_popup.next_level_button_pressed.connect(_on_next_level_button_pressed)
	#level_complete_popup.level_select_button_pressed.connect(_on_level_select_button_pressed)
	_number_level_buttons()
	#_music_fade_in()
	
func _number_level_buttons() -> void:
	var level_number: int = 1
	for child in get_children():
		if child is LevelButton:
			child.pressed.connect(func():
				_on_level_button_pressed(child))
			if level_number <= 2:
				child.level_number = 'T' + str(level_number)
			else:
				child.level_number = str(level_number-3)
			level_buttons.append(child)
			level_number += 1
			
func _on_level_button_pressed(button: LevelButton) -> void:
	#level_selection_music.stop()
	
	current_level_button = button
	current_level = button.level_scene.instantiate()
	current_level_number = level_buttons.find(button)
	#animation_player.play('fade_out')
	#await animation_player.animation_finished
	_enter_current_level()
	#animation_player.play('fade_in')
	
func _on_level_back_button_pressed() -> void:
	GameRoot.enter_level_select_screen()
	#animation_player.play('fade_out')
	#await animation_player.animation_finished
	#current_level.queue_free()
	#animation_player.play('fade_in')
	#
	#await animation_player.animation_finished
	#_music_fade_in()
	
func _on_level_restarted() -> void:
	GameRoot.enter_level(current_level_button.level_scene)
	
func _enter_current_level() -> void:
	GameRoot.enter_level(current_level_button.level_scene)
	
func _on_level_completed() -> void:
	current_level_button.level_complete = true
	_enable_next_level_button()
	
	GameRoot.level_complete()
	
#func _on_next_level_button_pressed() -> void:
	#_play_button_audio()
	#animation_player.play('fade_out')
	#await animation_player.animation_finished
	#current_level.queue_free()
	#level_complete_popup.hide()
	#current_level_number += 1
	#current_level_button = level_buttons[current_level_number]
	#_enter_current_level()
	#animation_player.play('fade_in')
	#await animation_player.animation_finished
	#
#func _on_level_select_button_pressed() -> void:
	#_play_button_audio()
	#animation_player.play('fade_out')
	#await animation_player.animation_finished
	#current_level.queue_free()
	#level_complete_popup.modulate = Color(1.0, 1.0, 1.0, 0.0)
	#level_complete_popup.hide()
	#animation_player.play('fade_in')
	#
	#await animation_player.animation_finished
	#_music_fade_in()
	
func _enable_next_level_button() -> void:
	var enable_next: bool = false
	var final_level: bool = true
	for child in get_children():
		if enable_next and child is LevelButton:
			child.disabled = false
			child.level_number_label.show()
			final_level = false
			break
		if child == current_level_button:
			enable_next = true
			
	if final_level:
		game_completed.emit()
		
func _play_button_audio() -> void:
	button_audio.volume_db = randf_range(-5, 0)
	button_audio.pitch_scale = randf_range(0.8, 1.2)
	button_audio.play(0.17)
		
func _on_back_button_pressed() -> void:
	_play_button_audio()
	GameRoot.enter_title_screen()
	
#func _music_fade_in() -> void:
	#level_selection_music.play()
	#var prev_db = level_selection_music.volume_db
	#level_selection_music.volume_db = prev_db - 10
	#var tween = get_tree().create_tween()
	#tween.tween_property(level_selection_music, 'volume_db', prev_db, 2)
