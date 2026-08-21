class_name MyButton
extends Button

func _ready() -> void:
	pressed.connect(_on_pressed)
	
func _on_pressed() -> void:
	HapticManager.trigger_button_haptic()
	AudioManager.play_button_click_sfx()
