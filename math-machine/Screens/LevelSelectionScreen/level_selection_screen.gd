extends Control

@onready var level_buttons_container: Node = %LevelButtonsContainer
@onready var back_button: Button = %BackButton
@onready var settings_button: Button = %SettingsButton

var level_buttons: Array[LevelButton] = [null]

func _ready() -> void:
	back_button.pressed.connect(_on_back_button_pressed)
	settings_button.pressed.connect(_on_settings_button_pressed)
	_init_level_buttons()
	
func update_level_buttons() -> void:
	var previous_level_complete: bool = false
	for level_button in level_buttons:
		if not level_button: continue
		if level_button.level_number >= LevelManager.levels.size(): continue
		if previous_level_complete:
			previous_level_complete = false
			level_button.disabled = false
		if LevelManager.levels_completed[level_button.level_number]:
			level_button.level_complete = true
			level_button.disabled = false
			previous_level_complete = true
	
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
			if level_number < LevelManager.levels.size() and LevelManager.levels_completed[level_number]:
				child.level_complete = true
				previous_level_complete = true
			else:
				previous_level_complete = false
			level_buttons.append(child)
			level_number += 1
			
func _on_level_button_pressed(button: LevelButton) -> void:
	var level: Level = LevelManager.get_level(button.level_number)
	GameRoot.enter_level(level)
	
func _on_back_button_pressed() -> void:
	AudioManager.play_button_click_sfx()
	GameRoot.enter_title_screen()
	
func _on_settings_button_pressed() -> void:
	AudioManager.play_button_click_sfx()
	GameRoot.enter_settings_screen()
	
#func _music_fade_in() -> void:
	#level_selection_music.play()
	#var prev_db = level_selection_music.volume_db
	#level_selection_music.volume_db = prev_db - 10
	#var tween = get_tree().create_tween()
	#tween.tween_property(level_selection_music, 'volume_db', prev_db, 2)
