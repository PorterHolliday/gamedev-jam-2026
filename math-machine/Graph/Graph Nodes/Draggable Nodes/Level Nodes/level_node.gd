@tool
class_name LevelNode
extends DraggableNode

@export var level: Level = null:
	set(new_val):
		if level:
			level.level_node = null
		level = new_val
		if level:
			level.level_node = self
			if level.level_number:
				value = level.level_number
			else:
				value = NULL_VALUE
			if Engine.is_editor_hint():
				_update_value_label()

var value: int = NULL_VALUE
@onready var value_label: Label = %ValueLabel

func _ready() -> void:
	super()
	if level and level.level_number: value = level.level_number
	_update_value_label()
	
func _gui_input(event: InputEvent) -> void:
	super(event)
	_right_click_to_enter_level(event)
	
func _right_click_to_enter_level(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_enter_level()
		
func _enter_level() -> void:
	level.enable()
	
func _update_value_label() -> void:
	if value == NULL_VALUE:
		value_label.text = '?'
	else:
		value_label.text = str(value)
