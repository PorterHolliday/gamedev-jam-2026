class_name HowToPlayScreen
extends Control

const TIME_BETWEEN_ANIMATIONS: float = 1.0
const CONNECT_SPEED: float = 300.0
const DRAG_TUTORIAL_START_POSITION: Vector2 = Vector2(768, 1536)
const DRAG_TUTORIAL_FINAL_POSITION: Vector2 = Vector2(384, 1536)

var disconnect_tutorial_connection: GraphCanvas.Connection
var tweens: Array[Tween] = []
var timers: Array[Timer] = []

@onready var up_arrow: TextureRect = %UpArrow
@onready var scroll_container: ScrollContainer = %ScrollContainer
@onready var graph_canvas: GraphCanvas = %GraphCanvas
@onready var output_node: OutputNode2 = %OutputNode
@onready var output_node_2: OutputNode2 = %OutputNode2
@onready var output_node_3: OutputNode2 = %OutputNode3
@onready var graph_canvas_2: GraphCanvas = %GraphCanvas2
@onready var input_node: InputNode2 = %InputNode
@onready var add_value_node: AddValueNode = %AddValueNode
@onready var pointer: Pointer = %Pointer
@onready var graph_canvas_3: GraphCanvas = %GraphCanvas3
@onready var input_node_2: InputNode2 = %InputNode2
@onready var add_value_node_2: AddValueNode = %AddValueNode2
@onready var add_value_node_3: AddValueNode = %AddValueNode3
@onready var pointer_2: Pointer = %Pointer2
@onready var graph_canvas_4: GraphCanvas = %GraphCanvas4
@onready var input_node_3: InputNode2 = %InputNode3
@onready var add_value_node_4: AddValueNode = %AddValueNode4
@onready var pointer_3: Pointer = %Pointer3
@onready var graph_canvas_5: GraphCanvas = %GraphCanvas5
@onready var add_value_node_5: AddValueNode = %AddValueNode5
@onready var pointer_4: Pointer = %Pointer4
@onready var graph_canvas_6: GraphCanvas = %GraphCanvas6
@onready var add_value_node_6: AddValueNode = %AddValueNode6
@onready var pointer_5: Pointer = %Pointer5
@onready var mouse: Mouse = %Mouse
@onready var back_button: Button = %BackButton

func _ready() -> void:
	back_button.pressed.connect(_on_back_button_pressed)
	graph_canvas.start()
	graph_canvas.mouse_position_override = Vector2.ONE
	graph_canvas_2.start()
	graph_canvas_2.mouse_position_override = Vector2.ONE
	graph_canvas_3.start()
	graph_canvas_3.mouse_position_override = Vector2.ONE
	graph_canvas_4.start()
	graph_canvas_4.mouse_position_override = Vector2.ONE
	graph_canvas_5.start()
	graph_canvas_5.mouse_position_override = Vector2.ONE
	graph_canvas_6.start()
	graph_canvas_6.mouse_position_override = Vector2.ONE
	start()

func start() -> void:
	scroll_container.set_deferred('scroll_vertical', 0)
	up_arrow.hide()
	await get_tree().create_timer(4.0).timeout
	_start_animations()

func _start_animations() -> void:
	_reset_disconnect_animation()
	
	_play_fill_targets_animation()
	_play_connect_animation()
	_play_multi_connect_animation()
	_play_disconnect_animation()
	_play_drag_animation()
	_play_node_info_animation()

func _play_fill_targets_animation() -> void:
	while can_process():
		await output_node._play_fill_animation()
		await get_tree().create_timer(0.5).timeout
		await output_node_2._play_fill_animation()
		await get_tree().create_timer(0.5).timeout
		await output_node_3._play_fill_animation()
		await get_tree().create_timer(1.5).timeout
		_reset_fill_targets_animation()
		await get_tree().create_timer(TIME_BETWEEN_ANIMATIONS).timeout

func _reset_fill_targets_animation() -> void:
	output_node.set_fill_progress(0.0)
	output_node_2.set_fill_progress(0.0)
	output_node_3.set_fill_progress(0.0)

func _play_connect_animation() -> void:
	while can_process():
		pointer.global_position = input_node.outputs[0].global_position
		pointer.show()
		await _play_connection_animation(input_node.outputs[0], add_value_node.inputs[0], graph_canvas_2, pointer)
		await get_tree().create_timer(0.5).timeout
		pointer.hide()
		await get_tree().create_timer(1.5).timeout
		_reset_connect_animation()
		await get_tree().create_timer(TIME_BETWEEN_ANIMATIONS).timeout
	
func _reset_connect_animation() -> void:
	graph_canvas_2.connections.clear.call_deferred()
	add_value_node.inputs[0].value = MyGraphNode.NULL_VALUE
	add_value_node.outputs[0].value = MyGraphNode.NULL_VALUE
	add_value_node.inputs[0].fill_panel.modulate = Color.WHITE
	
func _play_multi_connect_animation() -> void:
	while can_process():
		pointer_2.global_position = input_node_2.outputs[0].global_position
		pointer_2.show()
		await _play_connection_animation(input_node_2.outputs[0], add_value_node_2.inputs[0], graph_canvas_3, pointer_2)
		await get_tree().create_timer(0.5).timeout
		pointer_2.hide()
		await get_tree().create_timer(0.2).timeout
		pointer_2.global_position = input_node_2.outputs[0].global_position
		pointer_2.show()
		await _play_connection_animation(input_node_2.outputs[0], add_value_node_3.inputs[0], graph_canvas_3, pointer_2)
		await get_tree().create_timer(0.5).timeout
		pointer_2.hide()
		await get_tree().create_timer(1.5).timeout
		_reset_multi_connect_animation()
		await get_tree().create_timer(TIME_BETWEEN_ANIMATIONS).timeout

func _reset_multi_connect_animation() -> void:
	graph_canvas_3.connections.clear.call_deferred()
	add_value_node_2.inputs[0].value = MyGraphNode.NULL_VALUE
	add_value_node_2.outputs[0].value = MyGraphNode.NULL_VALUE
	add_value_node_3.inputs[0].value = MyGraphNode.NULL_VALUE
	add_value_node_3.outputs[0].value = MyGraphNode.NULL_VALUE

func _play_disconnect_animation() -> void:
	while can_process():
		pointer_3.position = Vector2(576, 1232)
		pointer_3.show()
		await get_tree().create_timer(0.5).timeout
		pointer_3.play_click_animation(0.5)
		graph_canvas_4.request_disconnection(disconnect_tutorial_connection, false)
		await get_tree().create_timer(1.0).timeout
		pointer_3.hide()
		await get_tree().create_timer(1.5).timeout
		_reset_disconnect_animation()
		await get_tree().create_timer(TIME_BETWEEN_ANIMATIONS).timeout

func _reset_disconnect_animation() -> void:
	if graph_canvas_4.connections.size() == 0:
		disconnect_tutorial_connection = GraphCanvas.Connection.new(input_node_3.outputs[0], add_value_node_4.inputs[0])
		graph_canvas_4.connections.append(disconnect_tutorial_connection)
	add_value_node_4.inputs[0].value = 2
	add_value_node_4.inputs[0].value_text_color = input_node_3.outputs[0].value_panel_color
	add_value_node_4.inputs[0].connected_color = input_node_3.outputs[0].connection_color
	add_value_node_4.outputs[0].value = 1
	
func _play_drag_animation() -> void:
	while can_process():
		pointer_4.position = DRAG_TUTORIAL_START_POSITION
		pointer_4.show()
		await get_tree().create_timer(0.5).timeout
		var tween: Tween = get_tree().create_tween()
		tween.tween_property(add_value_node_5, 'position', DRAG_TUTORIAL_FINAL_POSITION, 1.0)
		tween.parallel().tween_property(pointer_4, 'position', DRAG_TUTORIAL_FINAL_POSITION, 1.0)
		await tween.finished
		await get_tree().create_timer(0.5).timeout
		pointer_4.hide()
		await get_tree().create_timer(1.5).timeout
		_reset_drag_animation()
		await get_tree().create_timer(TIME_BETWEEN_ANIMATIONS).timeout
	
func _reset_drag_animation() -> void:
	add_value_node_5.position = DRAG_TUTORIAL_START_POSITION
	
func _play_node_info_animation() -> void:
	while can_process():
		pointer_5.global_position = add_value_node_6.global_position
		mouse.global_position = add_value_node_6.global_position
		
		if OS.has_feature('web_android') or OS.has_feature('web_ios'):
			pointer_5.show()
		else:
			mouse.show()
			
		await get_tree().create_timer(0.5).timeout
		
		# Animate long-press
		if OS.has_feature('web_android') or OS.has_feature('web_ios'):
			await pointer_5.play_click_animation(1.0)
		else:
			mouse.play_right_click_animation(0.5)
			
		var tween: Tween = get_tree().create_tween()
		tween.tween_method(
			func(_time: float):
				add_value_node_6.node_info.show(),
			0.0, 1.0, 3.0)
		await get_tree().create_timer(0.5).timeout
		pointer_5.hide()
		mouse.hide()
		await tween.finished
		_reset_node_info_animation()
		await get_tree().create_timer(TIME_BETWEEN_ANIMATIONS).timeout

func _reset_node_info_animation() -> void:
	add_value_node_6.node_info.hide()

func _play_connection_animation(from_port: GraphNodePort, to_port: GraphNodePort, graph_canvas: GraphCanvas, pointer: Pointer) -> GraphCanvas.Connection:
	graph_canvas.current_connection_start_port = from_port
	var distance: float = from_port.global_position.distance_to(to_port.global_position)
	var tween: Tween = get_tree().create_tween()
	tween.tween_method(
		func(weight: float):
			var new_position: Vector2 = from_port.global_position.lerp(to_port.global_position, weight)
			pointer.global_position = new_position
			graph_canvas.mouse_position_override = new_position - graph_canvas.global_position,
		0.0, 1.0, distance / CONNECT_SPEED
	)
	await tween.finished
	graph_canvas.current_connection_start_port = null
	return graph_canvas.request_connection(from_port, to_port, true)
	
func _on_back_button_pressed() -> void:
	GameRoot.exit_how_to_play_screen()
	
