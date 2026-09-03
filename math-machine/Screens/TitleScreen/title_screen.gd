extends Control

@onready var play_button: Button = %PlayButton
@onready var level_select_button: MyButton = %LevelSelectButton
@onready var settings_button: Button = %SettingsButton
@onready var credits_button: Button = %CreditsButton

func _ready() -> void:
	play_button.pressed.connect(_on_play_button_pressed)
	level_select_button.pressed.connect(_on_level_select_button_pressed)
	settings_button.pressed.connect(_on_settings_button_pressed)
	credits_button.pressed.connect(_on_credits_button_pressed)
	
	var deepest_incomplete_level_index: int = SaveManager.get_deepest_incomplete_level_index()
	if deepest_incomplete_level_index == -1:
		play_button.text = "LEVEL SELECT"
	elif not SaveManager.is_new_player():
		play_button.text = "CONTINUE"
		level_select_button.show()
	
func _on_play_button_pressed() -> void:
	var deepest_incomplete_level_index: int = SaveManager.get_deepest_incomplete_level_index()
	if deepest_incomplete_level_index == -1:
		GameRoot.enter_level_select_screen()
	else:
		GameRoot.enter_level(LevelManager.enter_level(deepest_incomplete_level_index))

func _on_level_select_button_pressed() -> void:
	GameRoot.enter_level_select_screen()

func _on_settings_button_pressed() -> void:
	GameRoot.enter_settings_screen()
	
func _on_credits_button_pressed() -> void:
	GameRoot.enter_credits_screen()
