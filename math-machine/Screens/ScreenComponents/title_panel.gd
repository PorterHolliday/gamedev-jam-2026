@tool
class_name TitlePanel
extends PanelContainer

@export var text: String = "":
	set(new_val):
		text = new_val
		if label:
			label.text = text
@export var color: Color = Color.WHITE:
	set(new_val):
		color = new_val
		self_modulate = color
@export var text_color: Color = Color.BLACK:
	set(new_val):
		text_color = new_val
		if label:
			label.self_modulate = text_color
@export var text_size: int = 64:
	set(new_val):
		text_size = new_val
		if label:
			label.label_settings.font_size = text_size
@export var text_outline_size: int = 4:
	set(new_val):
		text_outline_size = new_val
		if label:
			label.label_settings.outline_size = text_outline_size
		
@onready var label: Label = %Label

func _ready() -> void:
	label.text = text
	self_modulate = color
	label.self_modulate = text_color
	label.label_settings.font_size = text_size
	label.label_settings.outline_size = text_outline_size
