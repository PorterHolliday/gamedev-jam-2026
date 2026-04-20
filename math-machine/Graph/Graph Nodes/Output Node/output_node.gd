@tool
class_name OutputNode
extends MyGraphNode

signal received_valid_output

@onready var _input_label: Label = %InputLabel
@onready var _value_label: Label = %ValueLabel
@export var value: int = 1:
	set(new_val):
		value = new_val
		if Engine.is_editor_hint():
			_update_value_label()

var is_satisfied: bool = false

func _ready() -> void:
	_inputs = [NULL_VALUE]
	_update_value_label()
	
func update_input(port_idx: int, new_value: int) -> void:
	super(port_idx, new_value)
	_update_input_label()
	_check_if_satisfied()
	
func remove_input(port_idx: int) -> void:
	super(port_idx)
	_update_input_label()
	is_satisfied = false
	
func _check_if_satisfied() -> void:
	if _inputs[0] == value:
		is_satisfied = true
		received_valid_output.emit()
	else:
		is_satisfied = false
		
func _calculate_output() -> int:
	return NULL_VALUE
	
func _update_input_label() -> void:
	if _inputs[0] == NULL_VALUE:
		_input_label.text = ''
	else:
		_input_label.text = str(_inputs[0])

func _update_value_label() -> void:
	if not _value_label: return
	_value_label.text = str(value)
