extends Control

@onready var play_button: Button = %PlayButton
@onready var button_audio: AudioStreamPlayer = %ButtonAudio

func _ready() -> void:
	play_button.pressed.connect(_on_play_button_pressed)
	
	for child in get_children():
		if child is GPUParticles2D:
			child.preprocess = randf_range(child.lifetime, child.lifetime * 2)
	
func _on_play_button_pressed() -> void:
	button_audio.volume_db = randf_range(-5, 0)
	button_audio.pitch_scale = randf_range(0.8, 1.2)
	button_audio.play()
	GameRoot.enter_level_select_screen()
