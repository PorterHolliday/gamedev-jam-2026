class_name OperationNode
extends MyGraphNode

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
	
func _play_update_input_animation() -> void:
	var tween: Tween = get_tree().create_tween()
	tween.tween_property(self, 'scale', Vector2(1.1, 1.1), 0.1)
	tween.tween_property(self, 'scale', Vector2.ONE, 0.1)
	
func _play_remove_input_animation() -> void:
	var tween: Tween = get_tree().create_tween()
	tween.tween_property(self, 'rotation_degrees', -5.0, 0.05)
	tween.tween_property(self, 'rotation_degrees', 5, 0.1)
	tween.tween_property(self, 'rotation_degrees', 0, 0.05)
