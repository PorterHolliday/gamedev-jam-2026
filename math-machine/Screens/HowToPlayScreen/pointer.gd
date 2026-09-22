class_name Pointer
extends Node2D

@onready var sprite_2d: Sprite2D = %Sprite2D
@onready var click_sprite: Sprite2D = %ClickSprite
@onready var label: Label = %Label

func play_click_animation(duration: float) -> void:
	click_sprite.show()
	await get_tree().create_timer(duration).timeout
	click_sprite.hide()

func play_hover_animation(duration: float) -> void:
	label.visible_characters = 0
	var tween: Tween = get_tree().create_tween()
	tween.tween_property(label, "visible_characters", 1, duration / 4)
	tween.tween_property(label, "visible_characters", 2, duration / 4)
	tween.tween_property(label, "visible_characters", 3, duration / 4)
	tween.tween_interval(duration / 4)
	await tween.finished
	label.visible_characters = 0
