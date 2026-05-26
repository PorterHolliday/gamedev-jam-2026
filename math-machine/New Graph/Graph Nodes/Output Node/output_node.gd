@tool
class_name OutputNode2
extends MyGraphNode2

signal received_valid_output

@onready var _sprite: Sprite2D = %Sprite2D
@onready var _value_label: Label = %ValueLabel
@export var value: int = 1:
	set(new_val):
		value = new_val
		if Engine.is_editor_hint():
			_update_value_label()
@export var unsatisfied_color: Color = Color.WHITE:
	set(new_val):
		unsatisfied_color = new_val
		if not is_satisfied:
			_sprite.modulate = unsatisfied_color
@export var unsatisfied_text_color: Color = Color.BLACK:
	set(new_val):
		unsatisfied_text_color = new_val
		if not is_satisfied:
			_value_label.modulate = unsatisfied_text_color
@export var satisfied_color: Color
@export var satisfied_text_color: Color = Color.WHITE

@export var is_satisfied: bool = false:
	set(new_val):
		is_satisfied = new_val
		if is_satisfied:
			_sprite.modulate = satisfied_color
			_value_label.modulate = satisfied_text_color
		else:
			_sprite.modulate = unsatisfied_color
			_value_label.modulate = unsatisfied_text_color

func _ready() -> void:
	_update_value_label()
	if Engine.is_editor_hint(): return
	super()
	
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
