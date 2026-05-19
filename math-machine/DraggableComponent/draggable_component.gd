class_name DraggableComponent
extends Area2D

@onready var parent: Node2D = get_parent()
var is_clicked: bool = false
var is_mouse_in_area: bool = false
var mouse_offset: Vector2 = Vector2.ZERO

func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	
func _process(_delta: float) -> void:
	if not is_clicked: return
	
	parent.global_position = get_global_mouse_position() - mouse_offset
	
func _unhandled_input(event: InputEvent) -> void:
	if not is_mouse_in_area: return
	
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_mouse_clicked()
		else:
			_on_mouse_released()
	
func _on_mouse_clicked() -> void:
	is_clicked = true
	mouse_offset = get_global_mouse_position() - parent.global_position
	
func _on_mouse_released() -> void:
	is_clicked = false
	mouse_offset = Vector2.ZERO
	
func _on_mouse_entered() -> void:
	is_mouse_in_area = true
	
func _on_mouse_exited() -> void:
	is_mouse_in_area = false
