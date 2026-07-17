extends Node

const SAVE_PATH = "user://game_data.json"
var levels_completed: Array = []
var music_volume: float = 100.0
var sfx_volume: float = 100.0

func _ready() -> void:
	var game_data: Dictionary = load_game()
	if game_data.is_empty():
		_init_game_data()
	else:
		levels_completed = game_data.progress.levels_completed
		music_volume = game_data.settings.music_volume
		sfx_volume = game_data.settings.sfx_volume

func load_game() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
		
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	var content = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(content)
	if parse_result == OK:
		return json.get_data()
		
	return {}

func save_game() -> void:
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not file: 
		push_error('Error saving to ', SAVE_PATH)
		return
		
	var data: Dictionary = {
		'progress': {
			'levels_completed': levels_completed
		},
		'settings': {
			'music_volume': music_volume,
			'sfx_volume': sfx_volume
		}
	}
	file.store_string(JSON.stringify(data))
	file.close()
	print('Game saved successfully to browser IndexedDB!')
	
func _init_game_data() -> void:
	for level in LevelManager.level_scenes.size():
		levels_completed.append(false)
