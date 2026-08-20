class_name Mouse
extends Node2D

const MOUSE_TEXTURE = preload("uid://bbwy4g00nt8v2")
const MOUSE_RIGHT_CLICK_TEXTURE = preload("uid://wl2nejq204x4")

@onready var sprite_2d: Sprite2D = %Sprite2D

func play_right_click_animation(duration: float) -> void:
	sprite_2d.texture = MOUSE_RIGHT_CLICK_TEXTURE
	await get_tree().create_timer(duration).timeout
	sprite_2d.texture = MOUSE_TEXTURE
