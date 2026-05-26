class_name OperationNode2
extends MyGraphNode2

@onready var _draggable_component: DraggableComponent = %DraggableComponent

func _ready() -> void:
	super()
	_draggable_component.drag_started.connect(_on_drag_started)
	_draggable_component.drag_ended.connect(_on_drag_ended)
	
func _on_drag_started() -> void:
	pass
	
func _on_drag_ended() -> void:
	pass
