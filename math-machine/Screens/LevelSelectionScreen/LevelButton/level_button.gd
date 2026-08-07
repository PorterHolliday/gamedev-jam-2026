class_name LevelButton
extends MyButton

var level_number: int = 0:
	set(new_val):
		level_number = new_val
		if level_number < LevelManager.tutorial_count:
			text = 'T' + str(level_number + 1)
		else:
			text = str(level_number + 1 - LevelManager.tutorial_count)

var level_complete: bool = false:
	set(new_val):
		level_complete = new_val
		if level_complete:
			theme_type_variation = 'CompleteLevelButton'
