@tool
class_name InputNode2
extends MyGraphNode2

@onready var value_label: Label = %ValueLabel
@export var value: int = 5:
	set(new_val):
		value = new_val
		if Engine.is_editor_hint():
			_update_value_label()

func _ready() -> void:
	if Engine.is_editor_hint(): return
	super()
	outputs[0].value = value
	_update_value_label()
	
func _update_value_label() -> void:
	if not value_label: return
	value_label.text = str(value)
