class_name LevelButton
extends Button

@export var font_color: Color
@export var hover_font_color: Color

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
		level_number_label.visible = not level_complete

func _ready() -> void:
	level_number_label.label_settings = level_number_label.label_settings.duplicate()
	if not disabled:
		level_number_label.show()
	level_number_label.label_settings.font_color = font_color
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	
func _on_mouse_entered() -> void:
	if not disabled:
		level_number_label.show()
		level_number_label.label_settings.font_color = hover_font_color
		if level_complete:
			checkmark.hide()
	
func _on_mouse_exited() -> void:
	level_number_label.label_settings.font_color = font_color
	if level_complete:
		level_number_label.hide()
		checkmark.show()
	
