@tool
class_name OutputNode2
extends MyGraphNode2

signal received_valid_output

@onready var _value_label: Label = %ValueLabel
@export var value: int = 1:
	set(new_val):
		value = new_val
		if Engine.is_editor_hint():
			_update_value_label()

var is_satisfied: bool = false

func _ready() -> void:
	if Engine.is_editor_hint(): return
	
	super()
	_update_value_label()
	
func update_input(port: GraphNodePort, new_value: int) -> void:
	super(port, new_value)
	_check_if_satisfied()
	
func remove_input(port: GraphNodePort) -> void:
	super(port)
	is_satisfied = false
	
func _check_if_satisfied() -> void:
	if inputs[0].value == value:
		is_satisfied = true
		received_valid_output.emit()
	else:
		is_satisfied = false

func _update_value_label() -> void:
	if not _value_label: return
	_value_label.text = str(value)
