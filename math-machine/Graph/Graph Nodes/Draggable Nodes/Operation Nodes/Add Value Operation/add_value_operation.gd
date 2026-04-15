@tool
class_name AddValueOperation
extends OperationNode

@export var value: int = 3:
	set(new_val):
		value = new_val
		if Engine.is_editor_hint():
			_update_value_label()

@onready var value_label: Label = %ValueLabel

func _ready() -> void:
	_input_count = 1
	super()
	_update_value_label()

func _calculate_output() -> int:
	if _inputs[0] == NULL_VALUE:
		return NULL_VALUE
	return _inputs[0] + value

func _update_value_label() -> void:
	if value >= 0:
		value_label.text = '+ ' + str(value)
	else:
		value_label.text = '- ' + str(abs(value))
