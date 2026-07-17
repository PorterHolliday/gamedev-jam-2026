extends Node

@export var tutorial_count: int = 2
@export var level_scenes: Array[PackedScene] = []

var current_level_index = 0
var levels_completed: Array[bool]:
	get():
		return SaveManager.levels_completed

func get_current_level_scene() -> PackedScene:
	return level_scenes[current_level_index]

func get_next_level_scene() -> PackedScene:
	current_level_index += 1
	if current_level_index >= level_scenes.size(): return null
	return level_scenes[current_level_index]
	
func get_level_scene(index: int) -> PackedScene:
	if index >= level_scenes.size(): 
		push_error('LevelManager: trying to access level scene out of array bounds.')
		return null
	current_level_index = index
	return level_scenes[current_level_index]

func complete_current_level() -> void:
	levels_completed[current_level_index] = true
	SaveManager.save_game()
	GameRoot.level_complete()
