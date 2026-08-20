extends Node2D

@export var pointer: Pointer
@export var mouse: Mouse
@export var graph_canvas: GraphCanvas
@export var graph_node_index: int = 0

var active: bool = true
var graph_node: MyGraphNode

func _ready() -> void:
	if not get_parent().is_node_ready():
		await get_parent().ready
		
	_get_graph_node()
	graph_node.node_info_shown.connect(_on_node_info_shown)
	
	if OS.has_feature('web_android') or OS.has_feature('web_ios'):
		pointer.show()
	else:
		mouse.show()
	
	await get_tree().create_timer(0.5).timeout
	while active:
		await get_tree().create_timer(0.5).timeout
		await play_node_info_animation()
	
func _process(delta: float) -> void:
	if graph_node:
		global_position = graph_node.global_position

func play_node_info_animation() -> void:
	if OS.has_feature('web_android') or OS.has_feature('web_ios'):
		await pointer.play_click_animation(2.0)
	else:
		await mouse.play_right_click_animation(0.5)

func _get_graph_node() -> void:
	graph_node = graph_canvas.nodes[graph_node_index]

func _on_node_info_shown() -> void:
	active = false
	hide()
