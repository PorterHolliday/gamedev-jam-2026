class_name MyGraphNode
extends Node2D

signal node_info_shown

const GROW_SCALE: Vector2 = Vector2(1.15, 1.15)
const ROTATION_DEGREES: float = 10.0
const NULL_VALUE: int = 9223372036854775807
const NODE_INFO_TIME: float = 1.0

@export var mouse_detector: ClickableControl

var _graph_canvas: GraphCanvas
var inputs: Array[GraphNodePort] = []
var outputs: Array[GraphNodePort] = []
var _is_last_input_mouse: bool = false

@onready var node_info: NodeInfo = %NodeInfo
@onready var node_info_timer: Timer = Timer.new()

func _ready() -> void:
	if get_parent() is GraphCanvas:
		_graph_canvas = get_parent()
	_init_ports()
	mouse_detector.mouse_entered.connect(_on_mouse_entered)
	mouse_detector.mouse_exited.connect(_on_mouse_exited)
	mouse_detector.mouse_clicked.connect(_on_mouse_clicked)
	
	add_child(node_info_timer)
	node_info_timer.one_shot = true
	node_info_timer.timeout.connect(_on_node_info_timer_timeout)
	
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_is_last_input_mouse = false
	elif event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		_is_last_input_mouse = false
	elif event is InputEventMouse:
		_is_last_input_mouse = true
	
	if event is InputEventMouseButton and event.pressed:
		_cancel_tooltip()
	
func _init_ports() -> void:
	for child in get_children():
		if child is GraphNodePort:
			if child.type == GraphNodePort.Type.INPUT:
				inputs.append(child)
			else:
				outputs.append(child)
	
func is_input_connected(port: GraphNodePort) -> bool:
	return port.value != NULL_VALUE

func update_input(port: GraphNodePort, value: int) -> void:
	if port.value != NULL_VALUE and value == NULL_VALUE:
		_play_remove_input_animation()
	elif port.value != value:
		_play_update_input_animation()
	port.value = value
	_update_outputs()
	
func remove_input(port: GraphNodePort) -> void:
	if port.value != NULL_VALUE:
		_play_remove_input_animation()
	port.value = NULL_VALUE
	_update_outputs()
	
func _update_outputs() -> void:
	var new_outputs: Array[int] = _calculate_outputs()
	
	for i in range(outputs.size()):
		if new_outputs[i] == outputs[i].value: continue
		outputs[i].value = new_outputs[i]
		_graph_canvas.update_output_connections(outputs[i])
	
func _calculate_outputs() -> Array[int]:
	return []
	
func _play_update_input_animation() -> void:
	var tween: Tween = get_tree().create_tween()
	tween.tween_property(self, 'scale', GROW_SCALE, 0.1)
	tween.tween_property(self, 'scale', Vector2.ONE, 0.1)
	
func _play_remove_input_animation() -> void:
	var tween: Tween = get_tree().create_tween()
	tween.tween_property(self, 'rotation_degrees', -ROTATION_DEGREES, 0.05)
	tween.tween_property(self, 'rotation_degrees', ROTATION_DEGREES, 0.1)
	tween.tween_property(self, 'rotation_degrees', 0, 0.05)

func _on_mouse_entered() -> void:
	if _is_last_input_mouse:
		node_info_timer.start(NODE_INFO_TIME)
	
func _on_mouse_exited() -> void:
	_cancel_tooltip()
	
func _on_mouse_clicked(button: MouseButton) -> void:
	if button == MOUSE_BUTTON_RIGHT:
		_show_tooltip()
	
func _on_node_info_timer_timeout() -> void:
	_show_tooltip()
	
func _show_tooltip() -> void:
	node_info.show()
	node_info_shown.emit()
	
func _cancel_tooltip() -> void:
	node_info.hide()
	node_info_timer.stop()
