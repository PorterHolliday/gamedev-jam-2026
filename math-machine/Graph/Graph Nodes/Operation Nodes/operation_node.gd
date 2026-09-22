class_name OperationNode
extends MyGraphNode

@onready var _drag_control: DragControl = %DragControl

func _ready() -> void:
	super()
	_drag_control.drag_started.connect(_on_drag_started)
	_drag_control.drag_ended.connect(_on_drag_ended)
	
func _on_drag_started() -> void:
	scale = GROW_SCALE
	get_parent().move_child(self, get_parent().get_children().size())
	HapticManager.trigger_pickup_haptic()
	AudioManager.play_grab_sfx()
	node_info_timer.stop()
	
func _on_drag_ended() -> void:
	scale = Vector2.ONE
	HapticManager.trigger_drop_haptic()
	AudioManager.play_drop_sfx()
	
	if _is_last_input_mouse and _drag_control.get_rect().has_point(get_local_mouse_position()):
		node_info_timer.start(NODE_INFO_TIME)

func _on_mouse_entered() -> void:
	if _drag_control.is_dragging: return
	super()
