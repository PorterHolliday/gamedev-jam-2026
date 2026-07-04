class_name LevelButton
extends Button

@onready var audio_stream_player: AudioStreamPlayer = %AudioStreamPlayer

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

func _ready() -> void:
	pressed.connect(_on_pressed)
		
func _on_pressed() -> void:
	audio_stream_player.volume_db = randf_range(-5, 0)
	audio_stream_player.pitch_scale = randf_range(0.8, 1.2)
	audio_stream_player.play(0.17)
