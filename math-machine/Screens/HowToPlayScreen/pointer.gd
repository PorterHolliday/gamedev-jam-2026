class_name Pointer
extends Node2D

@onready var sprite_2d: Sprite2D = %Sprite2D
@onready var click_sprite: Sprite2D = %ClickSprite

func play_click_animation(duration: float) -> void:
	click_sprite.show()
	await get_tree().create_timer(duration).timeout
	click_sprite.hide()
