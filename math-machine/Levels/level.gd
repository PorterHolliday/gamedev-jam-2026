class_name Level
extends Control

@export var level_number: int = 0
@export var level_node: LevelNode = null

func _ready() -> void:
	global_position = Vector2.ZERO
	if level_node:
		disable()
		
func disable() -> void:
	hide()
	get_node('GraphEdit').process_mode = Node.PROCESS_MODE_DISABLED
	
func enable() -> void:
	show()
	get_node('GraphEdit').process_mode = Node.PROCESS_MODE_INHERIT
