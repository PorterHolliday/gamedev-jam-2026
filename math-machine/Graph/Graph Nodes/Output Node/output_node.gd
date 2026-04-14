@tool
class_name OutputNode
extends MyGraphNode

signal received_valid_output

@export var value: int = 1:
	set(new_val):
		value = new_val
		if Engine.is_editor_hint():
			_update_value_label()

@onready var value_label: Label = %ValueLabel


func _ready() -> void:
	_inputs = [NULL_VALUE]
	_update_value_label()
	
func update_input(port_idx: int, value: int) -> void:
	super(port_idx, value)
	_check_if_satisfied()
	
func _check_if_satisfied() -> void:
	if _inputs[0] == value:
		received_valid_output.emit()
		
func _calculate_output() -> int:
	return NULL_VALUE

func _update_value_label() -> void:
	value_label.text = str(value)
