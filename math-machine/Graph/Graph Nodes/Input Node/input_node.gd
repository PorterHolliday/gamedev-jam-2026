@tool
class_name InputNode
extends MyGraphNode

@export var value: int = 5:
	set(new_val):
		value = new_val
		if Engine.is_editor_hint():
			_update_value_label()

@onready var value_label: Label = %ValueLabel

func _ready() -> void:
	super()
	output = value
	_update_value_label()
	
func _update_value_label() -> void:
	value_label.text = str(value)
