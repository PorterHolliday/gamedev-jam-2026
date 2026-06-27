class_name LevelCompletePopup
extends Control

signal next_level_button_pressed
signal level_select_button_pressed

@onready var next_level_button: Button = %NextLevelButton
@onready var level_select_button: Button = %LevelSelectButton
@onready var animation_player: AnimationPlayer = %AnimationPlayer

func _ready() -> void:
	next_level_button.pressed.connect(next_level_button_pressed.emit)
	level_select_button.pressed.connect(level_select_button_pressed.emit)
	
func on_level_completed() -> void:
	animation_player.play('level_complete')
