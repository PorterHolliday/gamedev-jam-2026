@tool
class_name LevelButton
extends Button

signal level_completed

@onready var level_number_label: Label = $LevelNumberLabel
@onready var checkmark: TextureRect = %Checkmark

@export var _level_scene: PackedScene
var level_number: int = 0:
	set(new_val):
		level_number = new_val
		level_number_label.text = str(level_number)
var level: Level

var level_complete: bool = false:
	set(new_val):
		level_complete = new_val
		checkmark.visible = level_complete

func _ready() -> void:
	pressed.connect(_on_pressed)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	
func _on_pressed() -> void:
	_enter_level()
	
func _enter_level() -> void:
	level = _level_scene.instantiate()
	level.restarted.connect(_on_level_restarted)
	level.completed.connect(_on_level_completed)
	get_parent().add_child(level)
	
func _on_level_restarted() -> void:
	level.queue_free()
	_enter_level()
	
func _on_level_completed() -> void:
	level.completed.disconnect(_on_level_completed)
	level.queue_free()
	level_complete = true
	level_completed.emit()
	
func _on_mouse_entered() -> void:
	if not disabled:
		level_number_label.show()
		if level_complete:
			checkmark.hide()
	
func _on_mouse_exited() -> void:
	level_number_label.hide()
	if level_complete:
		checkmark.show()
	
