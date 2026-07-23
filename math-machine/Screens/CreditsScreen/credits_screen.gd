class_name CreditsScreen
extends Control

@onready var back_button: Button = %BackButton
@onready var animation_player: AnimationPlayer = %AnimationPlayer

func _ready() -> void:
	back_button.pressed.connect(_on_back_button_pressed)

func reset_animation() -> void:
	animation_player.play('RESET')
	animation_player.advance(0)

func logo_animation() -> void:
	animation_player.play('logo_fade')

func _on_back_button_pressed() -> void:
	AudioManager.play_button_click_sfx()
	GameRoot.enter_title_screen()
