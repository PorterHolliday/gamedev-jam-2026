class_name Mouse
extends Node2D

const MOUSE_TEXTURE = preload("uid://bbwy4g00nt8v2")
const MOUSE_RIGHT_CLICK_TEXTURE = preload("uid://wl2nejq204x4")

@export var graph_canvas: GraphCanvas
@export var graph_node_index: int = 0
@export var active: bool = false
@export var animation_duration: float = 0.5
@export var wait_duration: float = 0.5

var graph_node: MyGraphNode

@onready var sprite_2d: Sprite2D = %Sprite2D

func _ready() -> void:
	if not graph_canvas:
		return
	
	if not get_parent().is_node_ready():
		await get_parent().ready
		
	_get_graph_node()
	graph_node.node_info_shown.connect(_on_node_info_shown)
	
	while active:
		await get_tree().create_timer(wait_duration).timeout
		await play_right_click_animation(animation_duration)
	
func _process(delta: float) -> void:
	if graph_node:
		global_position = graph_node.global_position

func play_right_click_animation(duration: float) -> void:
	sprite_2d.texture = MOUSE_RIGHT_CLICK_TEXTURE
	await get_tree().create_timer(duration).timeout
	sprite_2d.texture = MOUSE_TEXTURE

func _get_graph_node() -> void:
	graph_node = graph_canvas.nodes[graph_node_index]

func _on_node_info_shown() -> void:
	active = false
	hide()
