class_name UIRoot
extends Control

@export var level_complete_popup_scene: PackedScene
@export var game_complete_popup_scene: PackedScene

func on_level_complete() -> void:
	var popup: LevelCompletePopup
	if LevelManager.current_level_index == LevelManager.level_scenes.size() - 1:
		popup = game_complete_popup_scene.instantiate()
	else:
		popup = level_complete_popup_scene.instantiate()
	add_child(popup)
