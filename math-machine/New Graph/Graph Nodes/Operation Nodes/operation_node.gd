class_name OperationNode2
extends MyGraphNode2

@onready var _drag_area_2d: DragArea2D = %DragArea2D

func _ready() -> void:
	super()
	_drag_area_2d.drag_started.connect(_on_drag_started)
	_drag_area_2d.drag_ended.connect(_on_drag_ended)
	
func _on_drag_started() -> void:
	scale = Vector2(1.1, 1.1)
	get_parent().move_child(self, get_parent().get_children().size())
	
func _on_drag_ended() -> void:
	scale = Vector2.ONE
