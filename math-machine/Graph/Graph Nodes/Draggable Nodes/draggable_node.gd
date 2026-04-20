class_name DraggableNode
extends MyGraphNode

var _dragging := false
var _drag_offset := Vector2.ZERO
var _snapping_enabled := false
var _snapping_distance := 0.0
var _position_offset := Vector2.ZERO

func _ready() -> void:
	super()
	
	_position_offset = position_offset
	_snapping_enabled = get_parent().snapping_enabled
	_snapping_distance = get_parent().snapping_distance
	for child in get_children():
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_PASS

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		_drag_offset = get_local_mouse_position()
		if _dragging:
			get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion and _dragging:
		_position_offset += event.relative / get_parent().zoom
		if not _snapping_enabled:
			position_offset = _position_offset
		else:
			position_offset = Vector2(Vector2i(_position_offset / _snapping_distance)) * _snapping_distance
		get_viewport().set_input_as_handled()
