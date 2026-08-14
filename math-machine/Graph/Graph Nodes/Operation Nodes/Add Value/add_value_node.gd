@tool
class_name AddValueNode
extends OperationNode

@onready var value_label: Label = %ValueLabel
@onready var output_info: PanelContainer = %OutputInfo
@export var value: int = 3:
	set(new_val):
		value = new_val
		if Engine.is_editor_hint():
			_update_value_label()
			_update_output_info()

func _ready() -> void:
	if not Engine.is_editor_hint():
		super()
	_update_value_label()
	_update_output_info()

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
		
func _update_output_info() -> void:
	if not output_info: return
	output_info.text = "A" + value_label.text
