class_name DraggableComponent
extends Area2D

signal drag_started
signal drag_ended

@export var min_position: Vector2 = Vector2.ZERO
@export var max_position: Vector2 = Vector2(1152, 648)
@export var snap_distance: Vector2 = Vector2(16, 16)

@onready var parent: Node2D = get_parent()
var is_clicked: bool = false
var is_mouse_in_area: bool = false
var mouse_offset: Vector2 = Vector2.ZERO

func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	
func _process(_delta: float) -> void:
	if not is_clicked: return
	
	var new_position: Vector2 = get_global_mouse_position() - mouse_offset
	new_position = Vector2(Vector2i((new_position + snap_distance / 2.0) / snap_distance)) * snap_distance
	parent.global_position = new_position.clamp(min_position, max_position)
	
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
	parent.scale = Vector2(1.1, 1.1)
	drag_started.emit()
	
func _on_mouse_released() -> void:
	is_clicked = false
	mouse_offset = Vector2.ZERO
	parent.scale = Vector2.ONE
	drag_ended.emit()
	
func _on_mouse_entered() -> void:
	is_mouse_in_area = true
	
func _on_mouse_exited() -> void:
	is_mouse_in_area = false
