extends Node

## Owns the ordered list of level scenes and tracks which level is active.
##
## Levels are instantiated on demand by [GameRoot] during a screen transition,
## so exactly one [Level] instance exists at a time. This node never holds a
## reference to a live level; [GameRoot] owns that lifetime.

@export var tutorial_count: int = 2
@export var level_data_list: Array[LevelData] = []

var current_level_index: int = 0

## Save keys for each entry in [member level_data_list], built lazily. Parallel to
## level_data_list, so _level_uids[n] identifies level_data_list[n].
var _level_uids: Array[String] = []

## Returns true if [param index] addresses a real level data resource.
func has_level(index: int) -> bool:
	return index >= 0 and index < level_data_list.size()

## Stable save key for the level at [param index]. Unlike the index itself, this
## survives levels being inserted, removed or reordered.
func get_level_uid(index: int) -> String:
	if not has_level(index):
		push_error('LevelManager: level index %d is out of bounds.' % index)
		return ''
	if _level_uids.is_empty():
		_build_level_uids()
	return _level_uids[index]

func is_level_completed(index: int) -> bool:
	return SaveManager.is_level_completed(get_level_uid(index))

## Returns level data at [param index] and makes it current.
## Returns null if the index is out of bounds.	
func get_level_data(index: int) -> LevelData:
	if not has_level(index):
		push_error('LevelManager: level index %d is out of bounds.' % index)
		return null
	current_level_index = index
	return level_data_list[index]

func complete_current_level() -> void:
	SaveManager.set_level_completed(get_level_uid(current_level_index))
	SaveManager.save_game()
	GameRoot.level_complete()

func _build_level_uids() -> void:
	_level_uids.resize(level_data_list.size())
	for index in level_data_list.size():
		_level_uids[index] = _uid_for(level_data_list[index])

## Falls back to the scene path if a UID cannot be resolved, so progress is
## still recorded against something stable rather than being silently dropped.
static func _uid_for(resource: Resource) -> String:
	var path: String = resource.resource_path
	var id: int = ResourceLoader.get_resource_uid(path)
	if id == ResourceUID.INVALID_ID:
		push_error('LevelManager: no UID for "%s"; using its path as the save key.' % path)
		return path
	return ResourceUID.id_to_text(id)
