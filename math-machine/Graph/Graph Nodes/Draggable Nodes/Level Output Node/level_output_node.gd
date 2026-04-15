class_name LevelOutputNode
extends DraggableNode

signal input_changed(new_val: int)
			
@onready var _input_label: Label = %InputLabel
@onready var _value_label: Label = %ValueLabel

func _ready() -> void:
	_inputs = [NULL_VALUE]
	_update_value_label()
	
func update_input(port_idx: int, new_value: int) -> void:
	super(port_idx, new_value)
	input_changed.emit(_inputs[0])
	_update_input_label()
	_update_value_label()
	
func remove_input(port_idx: int) -> void:
	super(port_idx)
	_update_input_label()
		
func _calculate_output() -> int:
	return NULL_VALUE
	
func _update_input_label() -> void:
	if _inputs[0] == NULL_VALUE:
		_input_label.text = ''
	else:
		_input_label.text = str(_inputs[0])

func _update_value_label() -> void:
	if _inputs[0] == NULL_VALUE:
		_value_label.text = '?'
	else:
		_value_label.text = str(_inputs[0])
