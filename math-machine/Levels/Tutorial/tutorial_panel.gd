@tool
extends PanelContainer

@export_multiline var text: String = "":
	set(new_val):
		text = new_val
		_update_label_text()
@export_multiline var mobile_text: String = "":
	set(new_val):
		mobile_text = new_val
		_update_label_text()
	
@onready var label: Label = %Label
	
func _ready() -> void:
	_update_label_text()
	
func _update_label_text() -> void:
	if not label: return
	
	if mobile_text and (OS.has_feature('web_android') or OS.has_feature('web_ios')):
		label.text = mobile_text
	else:
		label.text = text
