extends Control

@onready var back_button: Button = %BackButton
@onready var fade_out_animation_player: AnimationPlayer = %FadeOutAnimationPlayer
var current_level_button: LevelButton
var current_level: Level

func _ready() -> void:
	back_button.pressed.connect(_on_back_button_pressed)
	_number_level_buttons()
	
func _number_level_buttons() -> void:
	var level_number: int = 1
	for child in get_children():
		if child is LevelButton:
			child.pressed.connect(func():
				_on_level_button_pressed(child))
			child.level_number = level_number
			level_number += 1
			
func _on_level_button_pressed(button: LevelButton) -> void:
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
	
func _on_level_restarted() -> void:
	fade_out_animation_player.play('fade_out')
	await fade_out_animation_player.animation_finished
	current_level.queue_free()
	_enter_current_level()
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
	hide()
