@tool
extends PanelContainer

@export_multiline var text: String = "":
	set(new_val):
		text = new_val
		if Engine.is_editor_hint():
			_update_label_text()
	
@onready var label: Label = %Label
	
func _ready() -> void:
	_update_label_text()
	
func _update_label_text() -> void:
	print(label)
	label.text = text
