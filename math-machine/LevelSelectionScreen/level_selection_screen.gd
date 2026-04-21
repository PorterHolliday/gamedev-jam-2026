extends Control

func _ready() -> void:
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
