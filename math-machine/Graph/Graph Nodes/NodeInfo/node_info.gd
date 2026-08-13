class_name NodeInfo
extends Control

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if visible:
			hide()
