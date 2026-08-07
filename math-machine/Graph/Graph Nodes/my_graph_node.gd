class_name MyGraphNode
extends Node2D

const GROW_SCALE: Vector2 = Vector2(1.15, 1.15)
const ROTATION_DEGREES: float = 10.0

@onready var _graph_canvas: GraphCanvas

const NULL_VALUE: int = 9223372036854775807

var inputs: Array[GraphNodePort] = []
var outputs: Array[GraphNodePort] = []

func _ready() -> void:
	if get_parent() is GraphCanvas:
		_graph_canvas = get_parent()
	_init_ports()
	
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
