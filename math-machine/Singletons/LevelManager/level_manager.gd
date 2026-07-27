extends Node

## Owns the ordered list of level scenes and tracks which level is active.
##
## Levels are instantiated on demand by [GameRoot] during a screen transition,
## so exactly one [Level] instance exists at a time. This node never holds a
## reference to a live level; [GameRoot] owns that lifetime.

@export var tutorial_count: int = 2
@export var level_scenes: Array[PackedScene] = []

var current_level_index: int = 0

var levels_completed: Array:
	get():
		return SaveManager.levels_completed

## Returns true if [param index] addresses a real level scene.
func has_level(index: int) -> bool:
	return index >= 0 and index < level_scenes.size()

## Instantiates the level at [param index] and makes it current.
## Returns null if the index is out of bounds.
func instantiate_level(index: int) -> Level:
	if not has_level(index):
		push_error('LevelManager: level index %d is out of bounds.' % index)
		return null
	current_level_index = index
	return level_scenes[index].instantiate()

func complete_current_level() -> void:
	levels_completed[current_level_index] = true
	SaveManager.save_game()
	GameRoot.level_complete()
