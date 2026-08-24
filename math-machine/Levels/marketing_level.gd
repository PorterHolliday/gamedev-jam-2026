extends Node2D

@onready var graph_canvas: GraphCanvas = %GraphCanvas

func _ready() -> void:
	graph_canvas.start()
