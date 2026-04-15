class_name DraggableNode
extends MyGraphNode

var _dragging := false
var _drag_offset := Vector2.ZERO

func _ready() -> void:
	super()
	
	for child in get_children():
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_PASS

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and draggable:
		_dragging = event.pressed
		_drag_offset = get_local_mouse_position()
		if _dragging:
			get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion and _dragging:
		position_offset += event.relative / get_parent().zoom
		get_viewport().set_input_as_handled()
