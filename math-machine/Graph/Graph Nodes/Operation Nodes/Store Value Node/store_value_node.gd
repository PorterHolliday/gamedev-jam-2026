class_name StoreValueNode
extends OperationNode

var value: int = 0
@onready var value_label: Label = %ValueLabel


func _ready() -> void:
	_input_count = 1
	output = 0
	super()
	
func update_input(port_idx: int, new_value: int) -> void:
	super(port_idx, new_value)
	value = output
	_update_value_label()
	
func _calculate_output() -> int:
	if _inputs[0] == NULL_VALUE: return output
	return _inputs[0]
	
func _update_value_label() -> void:
	if value == NULL_VALUE:
		value_label.text = ''
	else:
		value_label.text = str(value)
