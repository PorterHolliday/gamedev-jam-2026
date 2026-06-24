@tool
class_name AddValueNode
extends OperationNode

@onready var value_label: Label = %ValueLabel
@export var value: int = 3:
	set(new_val):
		value = new_val
		if Engine.is_editor_hint():
			_update_value_label()

func _ready() -> void:
	_update_value_label()
	if Engine.is_editor_hint(): return
	super()

func _calculate_outputs() -> Array[int]:
	if inputs[0].value != NULL_VALUE:
		return [inputs[0].value + value]
	return [NULL_VALUE]

func _update_value_label() -> void:
	if not value_label: return
	if value >= 0:
		value_label.text = '+' + str(value)
	else:
		value_label.text = '−' + str(abs(value))
