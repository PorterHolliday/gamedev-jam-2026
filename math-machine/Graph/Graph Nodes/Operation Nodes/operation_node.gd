class_name OperationNode
extends MyGraphNode

@onready var _drag_control: DragControl = %DragControl

func _ready() -> void:
	super()
	_drag_control.drag_started.connect(_on_drag_started)
	_drag_control.drag_ended.connect(_on_drag_ended)
	
func _on_drag_started() -> void:
	scale = Vector2(1.1, 1.1)
	get_parent().move_child(self, get_parent().get_children().size())
	AudioManager.play_grab_sfx()
	
func _on_drag_ended() -> void:
	scale = Vector2.ONE
	AudioManager.play_drop_sfx()
