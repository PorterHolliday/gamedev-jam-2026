class_name MyGraphNode2
extends Node2D

@onready var _graph_canvas: GraphCanvas = get_parent()

const NULL_VALUE: int = 9223372036854775807

var inputs: Array[GraphNodePort] = []
var outputs: Array[GraphNodePort] = []

func _ready() -> void:
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
	port.value = value
	_update_outputs()
	
func remove_input(port: GraphNodePort) -> void:
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
