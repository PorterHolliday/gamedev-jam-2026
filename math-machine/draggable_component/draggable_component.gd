class_name DraggableComponent
extends Button

@onready var parent: Control = get_parent()
var mouse_offset: Vector2 = Vector2.ZERO

func _ready() -> void:
	focus_mode = Control.FOCUS_CLICK
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)
	
func _process(_delta: float) -> void:
	if not button_pressed: return
	
	print(parent.global_position, ' | ', get_global_mouse_position(), ' | ', mouse_offset)
	parent.position_offset = get_local_mouse_position() - mouse_offset
	print(parent.global_position, ' | ', get_global_mouse_position(), ' | ', mouse_offset)
	
func _on_button_down() -> void:
	print('down')
	mouse_offset = get_local_mouse_position() - parent.position_offset
	
func _on_button_up() -> void:
	print('up')
	mouse_offset = Vector2.ZERO
