class_name Level
extends Control

@export var level_number: int = 0
@export var level_node: LevelNode = null

@onready var graph_edit: MyGraphEdit = %GraphEdit
@onready var back_button: Button = %BackButton

var level_output_node: LevelOutputNode

var _is_complete: bool = false

func _ready() -> void:
	global_position = Vector2.ZERO
	if level_node:
		disable()
		
	for child in graph_edit.get_children():
		if child is LevelOutputNode:
			level_output_node = child
		
	graph_edit.level_complete.connect(_on_level_complete)
	back_button.pressed.connect(_on_back_button_pressed)
	
	print(level_output_node, ' ', level_node)
	if level_output_node and level_node:
		level_output_node.input_changed.connect(func(new_val): 
			level_node.update_output(new_val))
		
func disable() -> void:
	hide()
	get_node('GraphEdit').process_mode = Node.PROCESS_MODE_DISABLED
	
func enable() -> void:
	show()
	get_node('GraphEdit').process_mode = Node.PROCESS_MODE_INHERIT

func _on_back_button_pressed() -> void:
	disable()

# Hides level first time it is completed
func _on_level_complete() -> void:
	if _is_complete: return
	_is_complete = true
	disable()
