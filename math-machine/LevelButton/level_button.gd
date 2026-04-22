@tool
class_name LevelButton
extends Button

@onready var level_number_label: Label = $LevelNumberLabel
@onready var checkmark: TextureRect = %Checkmark

@export var level_scene: PackedScene
var level_number: int = 0:
	set(new_val):
		level_number = new_val
		level_number_label.text = str(level_number)

var level_complete: bool = false:
	set(new_val):
		level_complete = new_val
		checkmark.visible = level_complete

func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	
func _on_mouse_entered() -> void:
	if not disabled:
		level_number_label.show()
		if level_complete:
			checkmark.hide()
	
func _on_mouse_exited() -> void:
	level_number_label.hide()
	if level_complete:
		checkmark.show()
	
