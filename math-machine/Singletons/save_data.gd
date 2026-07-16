class_name SaveData
extends Resource

@export var levels_completed: Array[bool] = []

func save() -> void:
	ResourceSaver.save(self)
