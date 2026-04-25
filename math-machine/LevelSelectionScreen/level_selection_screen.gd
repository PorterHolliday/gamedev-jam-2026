extends Control

@onready var back_button: Button = %BackButton
@onready var fade_out_animation_player: AnimationPlayer = %FadeOutAnimationPlayer
@onready var button_audio: AudioStreamPlayer = %ButtonAudio
@onready var level_selection_music: AudioStreamPlayer = $LevelSelectionMusic
var current_level_button: LevelButton
var current_level: Level

func _ready() -> void:
	back_button.pressed.connect(_on_back_button_pressed)
	_number_level_buttons()
	_music_fade_in()
	
func _number_level_buttons() -> void:
	var level_number: int = 1
	for child in get_children():
		if child is LevelButton:
			child.pressed.connect(func():
				_on_level_button_pressed(child))
			if level_number <= 3:
				child.level_number = 'T' + str(level_number)
			else:
				child.level_number = str(level_number-3)
			level_number += 1
			
func _on_level_button_pressed(button: LevelButton) -> void:
	level_selection_music.stop()
	
	current_level_button = button
	current_level = button.level_scene.instantiate()
	fade_out_animation_player.play('fade_out')
	await fade_out_animation_player.animation_finished
	_enter_current_level()
	fade_out_animation_player.play('fade_in')
	
func _on_level_back_button_pressed() -> void:
	fade_out_animation_player.play('fade_out')
	await fade_out_animation_player.animation_finished
	current_level.queue_free()
	fade_out_animation_player.play('fade_in')
	
	await fade_out_animation_player.animation_finished
	_music_fade_in()
	
func _on_level_restarted() -> void:
	fade_out_animation_player.play('fade_out')
	await fade_out_animation_player.animation_finished
	
	var music_offset: float = current_level.music.get_playback_position()
	current_level.queue_free()
	_enter_current_level()
	current_level.music.play(music_offset)
	fade_out_animation_player.play('fade_in')
	
func _enter_current_level() -> void:
	current_level = current_level_button.level_scene.instantiate()
	current_level.back_button_pressed.connect(_on_level_back_button_pressed)
	current_level.restarted.connect(_on_level_restarted)
	current_level.completed.connect(_on_level_completed)
	add_child(current_level)
	
func _on_level_completed() -> void:
	fade_out_animation_player.play('fade_out')
	await fade_out_animation_player.animation_finished
	current_level.queue_free()
	fade_out_animation_player.play('fade_in')
	current_level_button.level_complete = true
	_enable_next_level_button()
	
	await fade_out_animation_player.animation_finished
	_music_fade_in()
	
func _enable_next_level_button() -> void:
	var enable_next: bool = false
	for child in get_children():
		if enable_next and child is LevelButton:
			child.disabled = false
			child.level_number_label.show()
			break
		if child == current_level_button:
			enable_next = true

func _on_back_button_pressed() -> void:
	button_audio.volume_db = randf_range(-5, 0)
	button_audio.pitch_scale = randf_range(0.8, 1.2)
	button_audio.play()
	hide()
	
func _music_fade_in() -> void:
	level_selection_music.play()
	var prev_db = level_selection_music.volume_db
	level_selection_music.volume_db = prev_db - 10
	var tween = get_tree().create_tween()
	tween.tween_property(level_selection_music, 'volume_db', prev_db, 2)
