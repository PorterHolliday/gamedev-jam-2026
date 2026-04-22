extends Control

@onready var back_button: Button = %BackButton

func _ready() -> void:
	back_button.pressed.connect(_on_back_button_pressed)
	
	_number_level_buttons()
	
func _number_level_buttons() -> void:
	var prev_child: LevelButton = null
	var level_number: int = 1
	for child in get_children():
		if child is LevelButton:
			if prev_child:
				prev_child.level_completed.connect(func():
					child.disabled = false)
			prev_child = child
			child.level_number = level_number
			level_number += 1

func _on_back_button_pressed() -> void:
	hide()
