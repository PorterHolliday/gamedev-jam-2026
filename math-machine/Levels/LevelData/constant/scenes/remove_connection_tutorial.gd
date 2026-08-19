extends Node2D

@export var graph_canvas: GraphCanvas
@export var pointer: Pointer

var active: bool = true

func _ready() -> void:
	graph_canvas.disconnection_occurred.connect(_on_disconnection_occurred)
	while active:
		await pointer.play_click_animation(0.5)
		await get_tree().create_timer(0.5).timeout
	
func _on_disconnection_occurred() -> void:
	active = false
	pointer.hide()
