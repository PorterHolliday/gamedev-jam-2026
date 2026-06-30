class_name LevelCompletePopup
extends Control

@onready var next_level_button: Button = %NextLevelButton
@onready var level_select_button: Button = %LevelSelectButton
@onready var animation_player: AnimationPlayer = %AnimationPlayer

func _ready() -> void:
	next_level_button.pressed.connect(_on_next_level_button_pressed)
	level_select_button.pressed.connect(_on_level_select_button_pressed)
	animation_player.play('level_complete')
	
func _on_next_level_button_pressed() -> void:
	GameRoot.enter_next_level()
	queue_free()
	
func _on_level_select_button_pressed() -> void:
	GameRoot.enter_level_select_screen()
	queue_free()
	
