@tool
class_name LevelNode
extends DraggableNode

@onready var value_label: Label = %ValueLabel

@export var level: Level = null:
	set(new_val):
		if level:
			level.level_node = null
		level = new_val
		if level:
			level.level_node = self
			if level.level_number:
				output = level.level_number
			else:
				output = NULL_VALUE
		else:
			output = NULL_VALUE

var _start_position := Vector2.ZERO

func _ready() -> void:
	super()
	if level and level.level_number: output = level.level_number
	_update_value_label()
	
func _gui_input(event: InputEvent) -> void:
	super(event)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_start_position = position_offset
		else:
			if position_offset == _start_position:
				_enter_level()
	#_right_click_to_enter_level(event)
	
func _right_click_to_enter_level(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_enter_level()
		
func _enter_level() -> void:
	level.enable() 
	
func update_output(new_val: int) -> void:
	output = new_val
	_update_value_label()
	
func _update_value_label() -> void:
	if not value_label: return
	
	if output == NULL_VALUE:
		value_label.text = '?'
	else:
		value_label.text = str(output)
