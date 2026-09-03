extends Node

## Persists player progress and settings.
##
## Progress is keyed by level scene UID rather than by position in
## [member LevelManager.level_scenes], so inserting, removing or reordering
## levels can never remap completion flags onto the wrong levels. Only completed
## levels are stored; absence means "not completed".

const SAVE_PATH: String = 'user://game_data.json'

## Save format version.
## [br]1: progress.levels_completed was an Array[bool] indexed by level order.
## [br]2: progress.completed_level_uids is an Array[String] of level UIDs.
const SAVE_VERSION: int = 2

var music_volume: float = 100.0
var sfx_volume: float = 100.0
var total_play_time: float = 0.0

## Used as a set. Values are always true; membership is what matters.
var _completed_level_uids: Dictionary[String, bool] = {}

## Whether the hint button's one-time idle glow has already been used up,
## either because it fired or because the player found the button on their
## own first. Once true, no level ever arms the idle timer again.
var _hint_glow_seen: bool = false

var _flush_save_callback: JavaScriptObject

func _ready() -> void:
	if OS.has_feature("web"):
		var window = JavaScriptBridge.get_interface("window")
		if window:
			_flush_save_callback = JavaScriptBridge.create_callback(_on_flush_save_requested)
			window.onGameFlushSave = _flush_save_callback
			
	if not LevelManager.is_node_ready():
		await LevelManager.ready
	_apply(await load_game())
	
## Called from JS (see custom_shell.html) when the tab is about to be
## hidden or closed. JavaScriptBridge callbacks always receive exactly one
## Array - the JS call's arguments - even when nothing was passed.
func _on_flush_save_requested(_args: Array) -> void:
	save_game()

#region Progress

func is_new_player() -> bool:
	return _completed_level_uids.is_empty()
	
func get_first_incomplete_level_index() -> int:
	for level_data in LevelManager.level_data_list:
		if not _completed_level_uids.has(LevelManager._uid_for(level_data)):
			return LevelManager.level_data_list.find(level_data)
	return -1
	
func get_deepest_incomplete_level_index() -> int:
	var deepest_complete_level_index: int = -1
	for i in range(LevelManager.level_data_list.size()):
		var level_data: LevelData = LevelManager.level_data_list[i]
		if _completed_level_uids.has(LevelManager._uid_for(level_data)):
			deepest_complete_level_index = i
	var deepest_incomplete_level_index: int = deepest_complete_level_index + 1
	if deepest_incomplete_level_index >= LevelManager.level_data_list.size():
		return -1
	return deepest_incomplete_level_index

func is_level_completed(uid: String) -> bool:
	return _completed_level_uids.get(uid, false)

func set_level_completed(uid: String, completed: bool = true) -> void:
	if uid.is_empty():
		push_error('SaveManager: refusing to record progress for an empty level UID.')
		return
	if completed:
		_completed_level_uids[uid] = true
	else:
		_completed_level_uids.erase(uid)

func has_seen_hint_glow() -> bool:
	return _hint_glow_seen

## Marks the hint button's idle glow as used up for good. Idempotent, and
## saves immediately so this can't be lost to a crash or a hard quit between
## the glow firing and the next level-complete save.
func mark_hint_glow_seen() -> void:
	if _hint_glow_seen:
		return
	_hint_glow_seen = true
	save_game()

#endregion

#region Serialisation

func save_game() -> void:
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not file:
		push_error('SaveManager: could not open %s for writing (%s).'
			% [SAVE_PATH, error_string(FileAccess.get_open_error())])
		return

	var data: Dictionary = {
		'version': SAVE_VERSION,
		'progress': {
			'completed_level_uids': _completed_level_uids.keys(),
			'hint_glow_seen': _hint_glow_seen,
			'total_play_time': total_play_time
		},
		'settings': {
			'music_volume': music_volume,
			'sfx_volume': sfx_volume
		}
	}
	file.store_string(JSON.stringify(data))	
	file.close()
	
	if OS.has_feature("wavedash"):
		WavedashSDK.upload_remote_file(SAVE_PATH)

## Returns the parsed save file, or an empty dictionary if it is missing,
## unreadable, malformed, or not a JSON object.
func load_game() -> Dictionary:
	if OS.has_feature("wavedash"):
		if await WavedashSDK.remote_file_exists(SAVE_PATH):
			await WavedashSDK.download_remote_file(SAVE_PATH)
	
	if not FileAccess.file_exists(SAVE_PATH):
		return {}

	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		push_error('SaveManager: could not open %s for reading (%s).'
			% [SAVE_PATH, error_string(FileAccess.get_open_error())])
		return {}
	var content: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	if json.parse(content) != OK:
		push_error('SaveManager: %s is not valid JSON (line %d: %s).'
			% [SAVE_PATH, json.get_error_line(), json.get_error_message()])
		return {}

	var data: Variant = json.get_data()
	if typeof(data) != TYPE_DICTIONARY:
		push_error('SaveManager: %s did not contain a JSON object.' % SAVE_PATH)
		return {}
	return data

## Populates state from [param data]. An empty dictionary yields a fresh save,
## so a missing file and a corrupt one follow the same path.
func _apply(data: Dictionary) -> void:
	var progress: Dictionary = data.get('progress', {})
	var settings: Dictionary = data.get('settings', {})

	music_volume = float(settings.get('music_volume', 100.0))
	sfx_volume = float(settings.get('sfx_volume', 100.0))
	total_play_time = float(progress.get('total_play_time', 0.0))

	_completed_level_uids.clear()
	_hint_glow_seen = bool(progress.get('hint_glow_seen', false))
	if int(data.get('version', SAVE_VERSION)) < 2:
		_migrate_v1_progress(progress.get('levels_completed', []))
		return

	for uid in progress.get('completed_level_uids', []):
		if uid is String and not uid.is_empty():
			_completed_level_uids[uid] = true

## Maps a version 1 positional array onto UIDs using the current level order.
## That is correct precisely because reordering has not happened yet - avoiding
## it from here on is why version 2 exists.
func _migrate_v1_progress(raw: Array) -> void:
	for index in mini(raw.size(), LevelManager.level_scenes.size()):
		if not bool(raw[index]):
			continue
		set_level_completed(LevelManager.get_level_uid(index))

#endregion
