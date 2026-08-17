class_name HowToPlayScreen
extends Control

const TIME_BETWEEN_ANIMATIONS: float = 1.0
const CONNECT_SPEED: float = 300.0
const DRAG_TUTORIAL_FINAL_POSITION: Vector2 = Vector2(704.0, 368.0)

var disconnect_tutorial_connection: GraphCanvas.Connection

@onready var graph_canvas: GraphCanvas = %GraphCanvas
@onready var output_node: OutputNode2 = %OutputNode
@onready var output_node_2: OutputNode2 = %OutputNode2
@onready var output_node_3: OutputNode2 = %OutputNode3
@onready var input_node: InputNode2 = %InputNode
@onready var input_node_2: InputNode2 = %InputNode2
@onready var input_node_3: InputNode2 = %InputNode3
@onready var add_value_node: AddValueNode = %AddValueNode
@onready var add_value_node_2: AddValueNode = %AddValueNode2
@onready var add_value_node_3: AddValueNode = %AddValueNode3
@onready var add_value_node_4: AddValueNode = %AddValueNode4
@onready var add_value_node_5: AddValueNode = %AddValueNode5
@onready var add_value_node_6: AddValueNode = %AddValueNode6
@onready var pointer: Pointer = %Pointer
@onready var mouse: Mouse = %Mouse

func _ready() -> void:
	graph_canvas.start()
	graph_canvas.mouse_position_override = Vector2.ONE
	_init_disconnect_tutorial()
	while true:
		await get_tree().create_timer(TIME_BETWEEN_ANIMATIONS).timeout
		await _play_fill_targets_animation()
		await get_tree().create_timer(TIME_BETWEEN_ANIMATIONS).timeout
		await _play_connect_animation()
		await get_tree().create_timer(TIME_BETWEEN_ANIMATIONS).timeout
		await _play_multi_connect_tutorial()
		await get_tree().create_timer(TIME_BETWEEN_ANIMATIONS).timeout
		await _play_disconnect_animation()
		await get_tree().create_timer(TIME_BETWEEN_ANIMATIONS).timeout
		await _play_drag_animation()
		await get_tree().create_timer(TIME_BETWEEN_ANIMATIONS).timeout
		await _play_node_info_animation()

func _play_fill_targets_animation() -> void:
	await output_node._play_fill_animation()
	await get_tree().create_timer(0.5).timeout
	await output_node_2._play_fill_animation()
	await get_tree().create_timer(0.5).timeout
	await output_node_3._play_fill_animation()
	await get_tree().create_timer(1.5).timeout
	output_node._play_fill_animation(true)
	output_node_2._play_fill_animation(true)
	await output_node_3._play_fill_animation(true)
	
func _play_connect_animation() -> void:
	pointer.global_position = input_node.outputs[0].global_position
	pointer.show()
	var connection: GraphCanvas.Connection = await _play_connection_animation(input_node.outputs[0], add_value_node.inputs[0])
	await get_tree().create_timer(0.5).timeout
	pointer.hide()
	await get_tree().create_timer(1.5).timeout
	graph_canvas.connections.erase(connection)
	add_value_node.inputs[0].value = MyGraphNode.NULL_VALUE
	add_value_node.outputs[0].value = MyGraphNode.NULL_VALUE
	add_value_node.inputs[0].fill_panel.modulate = Color.WHITE
	
func _play_multi_connect_tutorial() -> void:
	pointer.global_position = input_node_2.outputs[0].global_position
	pointer.show()
	var connection_1: GraphCanvas.Connection = await _play_connection_animation(input_node_2.outputs[0], add_value_node_2.inputs[0])
	await get_tree().create_timer(0.5).timeout
	pointer.hide()
	await get_tree().create_timer(0.2).timeout
	pointer.global_position = input_node_2.outputs[0].global_position
	pointer.show()
	var connection_2: GraphCanvas.Connection = await _play_connection_animation(input_node_2.outputs[0], add_value_node_3.inputs[0])
	await get_tree().create_timer(0.5).timeout
	pointer.hide()
	await get_tree().create_timer(1.5).timeout
	graph_canvas.connections.erase(connection_1)
	add_value_node_2.inputs[0].value = MyGraphNode.NULL_VALUE
	add_value_node_2.outputs[0].value = MyGraphNode.NULL_VALUE
	graph_canvas.connections.erase(connection_2)
	add_value_node_3.inputs[0].value = MyGraphNode.NULL_VALUE
	add_value_node_3.outputs[0].value = MyGraphNode.NULL_VALUE

func _init_disconnect_tutorial() -> void:
	disconnect_tutorial_connection = graph_canvas.request_connection(input_node_3.outputs[0], add_value_node_4.inputs[0], false)

func _play_disconnect_animation() -> void:
	pointer.global_position = Vector2(840, 208)
	pointer.show()
	await get_tree().create_timer(0.5).timeout
	pointer.play_click_animation(0.5)
	graph_canvas.request_disconnection(disconnect_tutorial_connection, false)
	await get_tree().create_timer(1.0).timeout
	pointer.hide()
	await get_tree().create_timer(1.5).timeout
	graph_canvas.connections.append(disconnect_tutorial_connection)
	add_value_node_4.inputs[0].value = 2
	add_value_node_4.outputs[0].value = 1
	
func _play_drag_animation() -> void:
	var original_position: Vector2 = add_value_node_5.global_position
	pointer.global_position = original_position
	pointer.show()
	await get_tree().create_timer(0.5).timeout
	var tween: Tween = get_tree().create_tween()
	tween.tween_property(add_value_node_5, 'global_position', DRAG_TUTORIAL_FINAL_POSITION, 1.0)
	tween.parallel().tween_property(pointer, 'global_position', DRAG_TUTORIAL_FINAL_POSITION, 1.0)
	await tween.finished
	await get_tree().create_timer(0.5).timeout
	pointer.hide()
	await get_tree().create_timer(1.5).timeout
	add_value_node_5.global_position = original_position
	
func _play_node_info_animation() -> void:
	pointer.global_position = add_value_node_6.global_position
	mouse.global_position = add_value_node_6.global_position
	
	if OS.has_feature('web_android') or OS.has_feature('web_ios'):
		pointer.show()
	else:
		mouse.show()
		
	await get_tree().create_timer(0.5).timeout
	
	# Animate long-press
	if OS.has_feature('web_android') or OS.has_feature('web_ios'):
		await pointer.play_click_animation(1.0)
	else:
		mouse.play_right_click_animation(0.5)
		
	var tween: Tween = get_tree().create_tween()
	tween.tween_method(
		func(_time: float):
			add_value_node_6.node_info.show(),
		0.0, 1.0, 3.0)
	await get_tree().create_timer(0.5).timeout
	pointer.hide()
	mouse.hide()
	await tween.finished
	add_value_node_6.node_info.hide()

func _play_connection_animation(from_port: GraphNodePort, to_port: GraphNodePort) -> GraphCanvas.Connection:
	graph_canvas.current_connection_start_port = from_port
	var distance: float = from_port.global_position.distance_to(to_port.global_position)
	var tween: Tween = get_tree().create_tween()
	tween.tween_method(
		func(current_position: Vector2):
			pointer.global_position = current_position
			graph_canvas.mouse_position_override = current_position / graph_canvas.scale,
		from_port.global_position, to_port.global_position, distance / CONNECT_SPEED
	)
	await tween.finished
	graph_canvas.current_connection_start_port = null
	return graph_canvas.request_connection(from_port, to_port, true)
	
