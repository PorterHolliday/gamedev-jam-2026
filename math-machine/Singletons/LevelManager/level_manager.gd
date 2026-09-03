extends Node

## Owns the ordered list of level scenes and tracks which level is active.
##
## Levels are instantiated on demand by [GameRoot] during a screen transition,
## so exactly one [Level] instance exists at a time. This node never holds a
## reference to a live level; [GameRoot] owns that lifetime.

@export var tutorial_count: int = 2
@export var level_data_list: Array[LevelData] = []

var current_level_index: int = -1

## Save keys for each entry in [member level_data_list], built lazily. Parallel to
## level_data_list, so _level_uids[n] identifies level_data_list[n].
var _level_uids: Array[String] = []

var hint_count: int = 0
var restart_count: int = 0
var total_level_time: float = 0.0
var current_run_time: float = 0.0

func _process(delta: float) -> void:
	if current_level_index > -1:
		total_level_time += delta
		current_run_time += delta

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
func enter_level(index: int) -> LevelData:
	var level_data: LevelData = _get_level_data(index)
	if level_data == null:
		return null
		
	current_level_index = index
	
	_track_level_start_analytics()
	
	return level_data
	
func restart_current_level() -> LevelData:
	_track_level_restart_analytics()
	return level_data_list[current_level_index]
	
func track_hint() -> void:
	hint_count += 1
	ByteBrew.track_event("hint_requested", {
		"level_id": get_level_uid(current_level_index),
		"level_name": _get_level_data(current_level_index).resource_path.get_file().get_basename(),
		"level_index": current_level_index,
		"hint_number": hint_count,
		"total_level_time": snapped(total_level_time, 0.1),
		"total_play_time": snapped(SaveManager.total_play_time, 0.1),
	})
	
func exit_level() -> void:
	_track_level_quit_analytics()
	current_level_index = -1

func complete_current_level() -> void:
	_track_level_complete_analytics()
	SaveManager.set_level_completed(get_level_uid(current_level_index))
	SaveManager.save_game()
	GameRoot.level_complete()
	
func _track_level_start_analytics() -> void:
	ByteBrew.track_event("level_start", {
		"level_id": get_level_uid(current_level_index),
		"level_name": _get_level_data(current_level_index).resource_path.get_file().get_basename(),
		"level_index": current_level_index,
		"total_play_time": snapped(SaveManager.total_play_time, 0.1),
	})
	total_level_time = 0.0
	current_run_time = 0.0
	restart_count = 0
	hint_count = 0
	
func _track_level_restart_analytics() -> void:
	restart_count += 1
	ByteBrew.track_event("level_restart", {
		"level_id": get_level_uid(current_level_index),
		"level_name": _get_level_data(current_level_index).resource_path.get_file().get_basename(),
		"level_index": current_level_index,
		"restart_number": restart_count,
		"current_run_time": snapped(current_run_time, 0.1),
		"total_play_time": snapped(SaveManager.total_play_time, 0.1),
	})
	current_run_time = 0.0
	
func _track_level_complete_analytics() -> void:
	ByteBrew.track_event("level_complete", {
		"level_id": get_level_uid(current_level_index),
		"level_name": _get_level_data(current_level_index).resource_path.get_file().get_basename(),
		"level_index": current_level_index,
		"status": "complete",
		"total_level_time": snapped(total_level_time, 0.1),
		"current_run_time": snapped(current_run_time, 0.1),
		"restart_count": restart_count,
		"hint_count": hint_count,
		"total_play_time": snapped(SaveManager.total_play_time, 0.1),
	})
	
func _track_level_quit_analytics() -> void:
	ByteBrew.track_event("level_quit", {
		"level_id": get_level_uid(current_level_index),
		"level_name": _get_level_data(current_level_index).resource_path.get_file().get_basename(),
		"level_index": current_level_index,
		"status": "quit",
		"total_level_time": snapped(total_level_time, 0.1),
		"current_run_time": snapped(current_run_time, 0.1),
		"restart_count": restart_count,
		"hint_count": hint_count,
		"total_play_time": snapped(SaveManager.total_play_time, 0.1),
	})
	
func _get_level_data(index: int) -> LevelData:
	if not has_level(index):
		push_error('LevelManager: level index %d is out of bounds.' % index)
		return null
	return level_data_list[index]

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
