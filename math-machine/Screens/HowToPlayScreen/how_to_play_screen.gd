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
@onready var graph_canvas_7: GraphCanvas = %GraphCanvas7
@onready var add_value_node_7: AddValueNode = %AddValueNode7
@onready var add_value_node_8: AddValueNode = %AddValueNode8
@onready var pointer_6: Pointer = %Pointer6
@onready var graph_canvas_8: GraphCanvas = %GraphCanvas8
@onready var add_value_node_9: AddValueNode = %AddValueNode9
@onready var add_value_node_10: AddValueNode = %AddValueNode10
@onready var pointer_7: Pointer = %Pointer7
@onready var graph_canvas_9: GraphCanvas = %GraphCanvas9
@onready var add_value_node_11: AddValueNode = %AddValueNode11
@onready var add_value_node_12: AddValueNode = %AddValueNode12
@onready var pointer_8: Pointer = %Pointer8
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
	graph_canvas_7.start()
	graph_canvas_7.mouse_position_override = Vector2.ONE
	graph_canvas_8.start()
	graph_canvas_8.mouse_position_override = Vector2.ONE
	graph_canvas_9.start()
	graph_canvas_9.mouse_position_override = Vector2.ONE
	reset()
	await _wait(0.5)
	_start_animations()

func reset() -> void:
	scroll_container.set_deferred('scroll_vertical', 0)
	up_arrow.hide()

func _start_animations() -> void:
	_reset_disconnect_animation()
	
	_play_fill_targets_animation()
	_play_connect_animation()
	_play_multi_connect_animation()
	_play_disconnect_animation()
	_play_drag_animation()
	_play_node_info_animation()
	_play_input_to_input_animation()
	_play_output_to_output_animation()
	_play_creates_loop_animation()

func _play_fill_targets_animation() -> void:
	while can_process():
		await output_node._play_fill_animation()
		await _wait(0.5)
		await output_node_2._play_fill_animation()
		await _wait(0.5)
		await output_node_3._play_fill_animation()
		await _wait(1.5)
		_reset_fill_targets_animation()
		await _wait(TIME_BETWEEN_ANIMATIONS)

func _reset_fill_targets_animation() -> void:
	output_node.set_fill_progress(0.0)
	output_node_2.set_fill_progress(0.0)
	output_node_3.set_fill_progress(0.0)

func _play_connect_animation() -> void:
	while can_process():
		pointer.global_position = input_node.outputs[0].global_position
		pointer.show()
		await _play_connection_animation(input_node.outputs[0], add_value_node.inputs[0], graph_canvas_2, pointer)
		await _wait(0.5)
		pointer.hide()
		await _wait(1.5)
		_reset_connect_animation()
		await _wait(TIME_BETWEEN_ANIMATIONS)
	
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
		await _wait(0.5)
		pointer_2.hide()
		await _wait(0.2)
		pointer_2.global_position = input_node_2.outputs[0].global_position
		pointer_2.show()
		await _play_connection_animation(input_node_2.outputs[0], add_value_node_3.inputs[0], graph_canvas_3, pointer_2)
		await _wait(0.5)
		pointer_2.hide()
		await _wait(1.5)
		_reset_multi_connect_animation()
		await _wait(TIME_BETWEEN_ANIMATIONS)

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
		await _wait(0.5)
		pointer_3.play_click_animation(0.5)
		graph_canvas_4.request_disconnection(disconnect_tutorial_connection, false)
		await _wait(1.0)
		pointer_3.hide()
		await _wait(1.5)
		_reset_disconnect_animation()
		await _wait(TIME_BETWEEN_ANIMATIONS)

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
		await _wait(0.5)
		var tween: Tween = _create_tween()
		tween.tween_property(add_value_node_5, 'position', DRAG_TUTORIAL_FINAL_POSITION, 1.0)
		tween.parallel().tween_property(pointer_4, 'position', DRAG_TUTORIAL_FINAL_POSITION, 1.0)
		await tween.finished
		await _wait(0.5)
		pointer_4.hide()
		await _wait(1.5)
		_reset_drag_animation()
		await _wait(TIME_BETWEEN_ANIMATIONS)
	
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
			
		await _wait(0.5)
		
		# Animate long-press
		if OS.has_feature('web_android') or OS.has_feature('web_ios'):
			await pointer_5.play_click_animation(1.0)
		else:
			mouse.play_right_click_animation(0.5)
			
		var tween: Tween = _create_tween()
		tween.tween_method(
			func(_time: float):
				add_value_node_6.node_info.show(),
			0.0, 1.0, 3.0)
		await _wait(0.5)
		pointer_5.hide()
		mouse.hide()
		await tween.finished
		_reset_node_info_animation()
		await _wait(TIME_BETWEEN_ANIMATIONS)

func _reset_node_info_animation() -> void:
	add_value_node_6.node_info.hide()
	
func _play_input_to_input_animation() -> void:
	while can_process():
		pointer_6.global_position = add_value_node_7.inputs[0].global_position
		pointer_6.show()
		await _play_connection_animation(add_value_node_7.inputs[0], add_value_node_8.inputs[0], graph_canvas_7, pointer_6)
		pointer_6.hide()
		_reset_input_to_input_animation()
		await _wait(TIME_BETWEEN_ANIMATIONS)
	
func _reset_input_to_input_animation() -> void:
	pass
	
func _play_output_to_output_animation() -> void:
	while can_process():
		pointer_7.global_position = add_value_node_9.outputs[0].global_position
		pointer_7.show()
		await _play_connection_animation(add_value_node_9.outputs[0], add_value_node_10.outputs[0], graph_canvas_8, pointer_7)
		pointer_7.hide()
		_reset_output_to_output_animation()
		await _wait(TIME_BETWEEN_ANIMATIONS)
	
func _reset_output_to_output_animation() -> void:
	pass
	
func _play_creates_loop_animation() -> void:
	while can_process():
		pointer_8.global_position = add_value_node_12.outputs[0].global_position
		pointer_8.show()
		await _play_connection_animation(add_value_node_12.outputs[0], add_value_node_11.inputs[0], graph_canvas_9, pointer_8)
		pointer_8.hide()
		_reset_creates_loop_animation()
		await _wait(TIME_BETWEEN_ANIMATIONS)
	
func _reset_creates_loop_animation() -> void:
	pass
	
func _play_connection_animation(from_port: GraphNodePort, to_port: GraphNodePort, graph_canvas: GraphCanvas, pointer: Pointer) -> void:
	pointer.global_position = from_port.global_position
	graph_canvas.mouse_position_override = from_port.global_position - graph_canvas.global_position
	graph_canvas.current_connection_start_port = from_port
	var distance: float = from_port.global_position.distance_to(to_port.global_position)
	var tween: Tween = _create_tween()
	tween.tween_method(
		func(weight: float):
			var new_position: Vector2 = from_port.global_position.lerp(to_port.global_position, weight)
			pointer.global_position = new_position
			graph_canvas.mouse_position_override = new_position - graph_canvas.global_position,
		0.0, 1.0, distance / CONNECT_SPEED
	)
	await tween.finished
	if graph_canvas._can_connect_ports(from_port, to_port):
		graph_canvas.request_connection(from_port, to_port, false)
	else:
		graph_canvas.is_current_connection_invalid = true
		to_port.bad_connection.show()
		await _wait(1.0)
		to_port.bad_connection.hide()
	
	graph_canvas.current_connection_start_port = null
	graph_canvas.current_connection_end_port = null
	
func _wait(duration: float) -> void:
	var timer: Timer = Timer.new()
	add_child(timer)
	timer.one_shot = true
	timer.start(duration)
	await timer.timeout
	timer.queue_free()
	
func _create_tween() -> Tween:
	return get_tree().create_tween().bind_node(self)
	
func _on_back_button_pressed() -> void:
	GameRoot.exit_how_to_play_screen()
	
