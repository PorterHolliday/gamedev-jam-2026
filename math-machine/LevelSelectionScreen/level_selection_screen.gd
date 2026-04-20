extends Control

func _ready() -> void:
	var prev_child: LevelButton = null
	for child in get_children():
		if child is LevelButton:
			if prev_child:
				prev_child.level_completed.connect(func():
					child.disabled = false)
			prev_child = child
