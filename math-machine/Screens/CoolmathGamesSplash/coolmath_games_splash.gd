class_name CoolmathGamesSplash
extends Control

signal animation_finished

@onready var texture_rect: TextureRect = %TextureRect

func _ready() -> void:
	texture_rect.modulate = Color.TRANSPARENT
	
	var tween: Tween = get_tree().create_tween()
	tween.tween_interval(0.25)
	tween.tween_property(texture_rect, "modulate", Color.WHITE, 0.5)
	tween.tween_interval(1.5)
	tween.tween_property(texture_rect, "modulate", Color.TRANSPARENT, 0.5)
	tween.tween_interval(0.25)
	await tween.finished
	
	animation_finished.emit()
