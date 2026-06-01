class_name ClickableArea2D
extends Area2D

signal mouse_clicked(button_index: MouseButton)
signal mouse_released(button_index: MouseButton)

var is_clicked: bool = false
var is_mouse_in_area: bool = false

func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	
func _unhandled_input(event: InputEvent) -> void:
	if not is_mouse_in_area: return
	
	if event is InputEventMouseButton:
		if event.pressed:
			is_clicked = true
			mouse_clicked.emit(event.button_index)
		else:
			is_clicked = false
			mouse_released.emit(event.button_index)
	
func _on_mouse_entered() -> void:
	is_mouse_in_area = true
	
func _on_mouse_exited() -> void:
	is_mouse_in_area = false
