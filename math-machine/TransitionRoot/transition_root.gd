class_name TransitionRoot
extends Control

@export var transition_duration: float = 0.25;

@onready var black: TextureRect = %Black

func transition_in() -> void:
	black.show()
	black.self_modulate = Color(0.0, 0.0, 0.0, 0.0)
	var tween: Tween = get_tree().create_tween()
	tween.tween_property(black, 'self_modulate', Color(0.0, 0.0, 0.0, 1.0), transition_duration)
	await tween.finished
	
func transition_out() -> void:
	black.self_modulate = Color()
	var tween: Tween = get_tree().create_tween()
	tween.tween_property(black, 'self_modulate', Color(0.0, 0.0, 0.0, 0.0), transition_duration)
	
	await tween.finished
	black.hide()
