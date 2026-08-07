extends Control

@onready var back_button: Button = %BackButton
@onready var settings_button: Button = %SettingsButton

## Parallel to LevelManager.level_scenes: level_buttons[n].level_number == n.
var level_buttons: Array[LevelButton] = []

func _ready() -> void:
	back_button.pressed.connect(_on_back_button_pressed)
	settings_button.pressed.connect(_on_settings_button_pressed)
	_init_level_buttons()
	
func update_level_buttons() -> void:
	var previous_level_complete: bool = false
	for level_button in level_buttons:
		if level_button.level_number >= LevelManager.level_data_list.size(): continue
		if previous_level_complete:
			previous_level_complete = false
			level_button.disabled = false
		if LevelManager.is_level_completed(level_button.level_number):
			level_button.level_complete = true
			level_button.disabled = false
			previous_level_complete = true
	
func _init_level_buttons() -> void:
	var level_number: int = 0
	var previous_level_complete = false
	_recursive_get_level_buttons(self, level_buttons)
	for level_button in level_buttons:
		level_button.pressed.connect(func():
				_on_level_button_pressed(level_button))
		level_button.level_number = level_number
		if previous_level_complete:
			level_button.disabled = false
		if LevelManager.has_level(level_number) and LevelManager.is_level_completed(level_number):
			level_button.level_complete = true
			previous_level_complete = true
		else:
			previous_level_complete = false
		level_number += 1
			
func _recursive_get_level_buttons(current_node: Node, button_array: Array[LevelButton]) -> void:
	for child in current_node.get_children():
		if child is LevelButton:
			button_array.append(child)
			continue
		_recursive_get_level_buttons(child, button_array)
	
func _on_level_button_pressed(button: LevelButton) -> void:
	GameRoot.enter_level(button.level_number)
	
func _on_back_button_pressed() -> void:
	GameRoot.enter_title_screen()
	
func _on_settings_button_pressed() -> void:
	GameRoot.enter_settings_screen()
