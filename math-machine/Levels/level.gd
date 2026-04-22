class_name Level
extends Control

signal restarted
signal completed

@onready var graph_edit: MyGraphEdit = %GraphEdit
@onready var back_button: Button = %BackButton
@onready var restart_button: Button = %RestartButton
@onready var hint_button: Button = %HintButton
@onready var hint: Label = %Hint
@onready var animation_player: AnimationPlayer = %AnimationPlayer

var level_output_node: LevelOutputNode

func _ready() -> void:
	global_position = Vector2.ZERO
		
	for child in graph_edit.get_children():
		if child is LevelOutputNode:
			level_output_node = child
		
	graph_edit.level_complete.connect(_on_level_complete)
	back_button.pressed.connect(_on_back_button_pressed)
	restart_button.pressed.connect(_on_restart_button_pressed)
	hint_button.pressed.connect(_on_hint_button_pressed)
		
func disable() -> void:
	hide()
	graph_edit.process_mode = Node.PROCESS_MODE_DISABLED
	
func enable() -> void:
	show()
	graph_edit.process_mode = Node.PROCESS_MODE_INHERIT

func _on_back_button_pressed() -> void:
	queue_free()
	
func _on_restart_button_pressed() -> void:
	restarted.emit()
	
func _on_hint_button_pressed() -> void:
	hint.show()

# Hides level first time it is completed
func _on_level_complete() -> void:
	hint.hide()
	animation_player.play('level_complete')
	await animation_player.animation_finished
	completed.emit()
