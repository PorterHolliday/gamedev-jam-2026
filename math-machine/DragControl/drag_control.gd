class_name DragControl
extends ClickableControl

signal drag_started
signal drag_ended

@export var drag_button_indexes: Array[MouseButton] = []
@export var min_position: Vector2 = Vector2.ZERO
@export var max_position: Vector2 = Vector2(1152, 648)
@export var snap_distance: Vector2 = Vector2(16, 16)

@onready var parent: Node2D = get_parent()
var mouse_offset: Vector2 = Vector2.ZERO
var is_dragging: bool = false

func _ready() -> void:
	super()
	mouse_clicked.connect(_on_mouse_clicked)
	mouse_released.connect(_on_mouse_released)
	
func _process(_delta: float) -> void:
	if not is_dragging: return
	
	var new_position: Vector2 = get_global_mouse_position() - mouse_offset
	new_position = Vector2(Vector2i((new_position + snap_distance / 2.0) / snap_distance)) * snap_distance
	parent.global_position = new_position.clamp(min_position, max_position)
	
func _on_mouse_clicked(button_index: MouseButton) -> void:
	if not drag_button_indexes.has(button_index): return
	if is_dragging: return
	is_dragging = true
	mouse_offset = get_global_mouse_position() - parent.global_position
	drag_started.emit()
	
func _on_mouse_released(button_index: MouseButton) -> void:
	if not drag_button_indexes.has(button_index): return
	if not is_dragging: return
	is_dragging = false
	mouse_offset = Vector2.ZERO
	drag_ended.emit()
