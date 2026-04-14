class_name OperationNode
extends MyGraphNode

var _dragging := false
var _drag_offset := Vector2.ZERO

var _input_labels: Array[Label] = []
var _output_label: Label

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		_drag_offset = get_local_mouse_position()
		if _dragging:
			get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion and _dragging:
		position_offset += event.relative / get_parent().zoom
		get_viewport().set_input_as_handled()
		
func update_input(port_idx: int, value: int) -> void:
	super(port_idx, value)
	_update_input_label(port_idx)
	
func remove_input(port_idx: int) -> void:
	super(port_idx)
	_update_input_label(port_idx)
	
func _update_input_label(port_idx: int) -> void:
	var slot: int = get_input_port_slot(port_idx)
	
	if _inputs[slot] == NULL_VALUE:
		_input_labels[slot].text = ''
	else:
		_input_labels[slot].text = str(_inputs[slot])

func _update_output() -> void:
	super()
	
	if _output == NULL_VALUE:
		_output_label.text = ''
	else:
		_output_label.text = str(_output)
