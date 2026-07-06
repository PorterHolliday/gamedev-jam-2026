class_name SettingsData
extends Resource

@export var music_volume: float = 0.0:
	set(new_val):
		music_volume = clampf(new_val, 0.0, 100.0)
@export var sfx_volume: float = 0.0:
	set(new_val):
		sfx_volume = clampf(new_val, 0.0, 100.0)

func save() -> void:
	ResourceSaver.save(self)
