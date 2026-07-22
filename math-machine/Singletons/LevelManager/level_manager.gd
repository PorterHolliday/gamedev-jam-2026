extends Node

@export var tutorial_count: int = 2
@export var level_scenes: Array[PackedScene] = []

var levels: Array[Level] = []
var current_level_index = 0
var levels_completed: Array[bool]:
	get():
		return SaveManager.levels_completed
var spare_level_instance: Level

func _ready() -> void:
	for level_scene in level_scenes:
		levels.append(level_scene.instantiate())

#func get_current_level_scene() -> PackedScene:
	#return level_scenes[current_level_index]
#
#func get_next_level_scene() -> PackedScene:
	#current_level_index += 1
	#if current_level_index >= level_scenes.size(): return null
	#return level_scenes[current_level_index]
	#
#func get_level_scene(index: int) -> PackedScene:
	#if index >= level_scenes.size(): 
		#push_error('LevelManager: trying to access level scene out of array bounds.')
		#return null
	#current_level_index = index
	#return level_scenes[current_level_index]
	
func get_current_level() -> Level:
	return levels[current_level_index]
	
func get_next_level() -> Level:
	current_level_index += 1
	if current_level_index >= levels.size(): return null
	_prepare_spare_instance.call_deferred()
	return levels[current_level_index]
	
func get_level(index: int) -> Level:
	if index >= levels.size(): 
		push_error('LevelManager: trying to access level scene out of array bounds.')
		return null
	current_level_index = index
	_prepare_spare_instance.call_deferred()
	return levels[current_level_index]
	
func get_spare_level_instance(prepare: bool = true) -> Level:
	var spare: Level = spare_level_instance
	spare_level_instance = null
	if prepare:
		_prepare_spare_instance.call_deferred()
	return spare

func complete_current_level() -> void:
	levels_completed[current_level_index] = true
	SaveManager.save_game()
	GameRoot.level_complete()
	
func replace_current_level(spare: Level) -> void:
	levels[current_level_index].queue_free()
	levels[current_level_index] = spare
	
func _prepare_spare_instance() -> void:
	if spare_level_instance:
		spare_level_instance.queue_free()
	
	var instance: Level = level_scenes[current_level_index].instantiate()
	GameRoot.node.game_screen_root.add_child(instance)  # parented once, stays parented
	instance.hide()
	instance.process_mode = Node.PROCESS_MODE_DISABLED
	spare_level_instance = instance
