extends Node2D

const pointer_offset: Vector2 = Vector2(0, 120)

@export var pointer: Pointer
@export var graph_canvas: GraphCanvas
@export var graph_node_index: int = 0

var active: bool = true
var graph_node: MyGraphNode

func _ready() -> void:
	if not get_parent().is_node_ready():
		await get_parent().ready
		
	_get_graph_node()
	graph_node.node_info_shown.connect(_on_node_info_shown)
	
	pointer.position = pointer_offset
	
	await get_tree().create_timer(0.5).timeout
	pointer.show()
	while active:
		await get_tree().create_timer(0.5).timeout
		await play_node_info_animation()
	
func _process(delta: float) -> void:
	if graph_node:
		global_position = graph_node.global_position

func play_node_info_animation() -> void:
	pointer.position = pointer_offset
	
	var tween: Tween = get_tree().create_tween()
	tween.tween_property(pointer, "position", Vector2.ZERO, 0.75)
	
	await tween.finished
	
	# Animate long-press
	if DeviceInfo.is_mobile:
		await pointer.play_click_animation(ClickableControl.TOUCH_TO_RIGHT_CLICK_TIME * 1.5)
	else:
		await pointer.play_hover_animation(MyGraphNode.NODE_INFO_TIME * 1.5)
	
	await get_tree().create_timer(1.0).timeout
		
	tween = get_tree().create_tween()
	tween.tween_property(pointer, "position", pointer_offset, 0.75)
	await tween.finished		

func _get_graph_node() -> void:
	graph_node = graph_canvas.nodes[graph_node_index]

func _on_node_info_shown() -> void:
	active = false
	hide()
