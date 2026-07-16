extends Node

@export var tutorial_count: int = 2
@export var level_scenes: Array[PackedScene] = []

const save_data_path: String = "res://Singletons/save_data.tres"
var current_level_index = 0
var levels_completed: Array[bool] = []
var save_data: SaveData

func _ready() -> void:
	_load_save_data()
	levels_completed = save_data.levels_completed
	print(levels_completed)

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
	save_data.levels_completed = levels_completed
	save_data.save()
	GameRoot.level_complete()

func _load_save_data() -> void:
	if FileAccess.file_exists(save_data_path):
		save_data = load(save_data_path)
		return
	save_data = SaveData.new()
	for level_scene in level_scenes:
		save_data.levels_completed.append(false)
	save_data.resource_path = save_data_path
