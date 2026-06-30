class_name UIRoot
extends Control

@export var level_complete_popup_scene: PackedScene

func on_level_complete() -> void:
	var level_complete_popup: LevelCompletePopup = level_complete_popup_scene.instantiate()
	add_child(level_complete_popup)
