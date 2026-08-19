@tool
extends CenterContainer

@export var text: String = "":
	set(new_val):
		text = new_val
		_update_title()
@export var color: Color = Color.WHITE:
	set(new_val):
		color = new_val
		_update_title()
@export var text_color: Color = Color.BLACK:
	set(new_val):
		text_color = new_val
		_update_title()
@export var panel_min_size: Vector2 = Vector2(80.0, 96.0):
	set(new_val):
		panel_min_size = new_val
		_update_title()
@export var spacer_min_size: float = 40.0:
	set(new_val):
		spacer_min_size = new_val
		_update_title()
@export var text_size: int = 64:
	set(new_val):
		text_size = new_val
		_update_title()
@export var text_outline_size: int = 4:
	set(new_val):
		text_outline_size = new_val
		_update_title()

@onready var title_panel_scene: PackedScene = preload("res://Screens/ScreenComponents/title_panel.tscn")
@onready var title_spacer_scene: PackedScene = preload("res://Screens/ScreenComponents/title_spacer.tscn")
@onready var h_box_container: HBoxContainer = %HBoxContainer

func _ready() -> void:
	_update_title()

func _update_title() -> void:
	if not h_box_container:
		return
		
	while h_box_container.get_children().size() > 0:
		var child: Node = h_box_container.get_child(0)
		h_box_container.remove_child(child)
		child.queue_free()
	
	for i in range(text.length()):
		if text[i] == " ":
			var spacer: Control = title_spacer_scene.instantiate()
			spacer.custom_minimum_size.x = spacer_min_size
			h_box_container.add_child(spacer)
			continue
			
		var title_panel: TitlePanel = title_panel_scene.instantiate()
		title_panel.get_node("Label").label_settings = title_panel.get_node("Label").label_settings.duplicate()
		title_panel.text = text[i]
		title_panel.color = color
		title_panel.text_color = text_color
		title_panel.custom_minimum_size = panel_min_size
		title_panel.text_size = text_size
		title_panel.text_outline_size = text_outline_size
		h_box_container.add_child(title_panel)
