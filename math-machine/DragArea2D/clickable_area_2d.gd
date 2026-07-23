class_name ClickableArea2D 
extends Area2D

signal mouse_clicked(button_index: MouseButton)
signal mouse_released(button_index: MouseButton)

var is_clicked: bool = false

func _input_event(_viewport: Viewport, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton:
		if event.pressed:
			is_clicked = true
			mouse_clicked.emit(event.button_index)
			get_viewport().set_input_as_handled() 
		else:
			is_clicked = false
			mouse_released.emit(event.button_index)

			get_viewport().set_input_as_handled()
