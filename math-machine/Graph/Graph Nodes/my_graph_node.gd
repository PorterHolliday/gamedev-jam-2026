class_name MyGraphNode
extends GraphNode

@onready var _graph_edit: MyGraphEdit = get_parent()

var _inputs: Array[int] = []
const NULL_VALUE: int = 9223372036854775807
var _output: int = NULL_VALUE
var _output_port_idx: int = 0

func _ready() -> void:
	pass

func update_input(port_idx: int, value: int) -> void:
	var slot_idx: int = get_input_port_slot(port_idx)
	_inputs[slot_idx] = value
	_update_output()
	
func remove_input(port_idx: int) -> void:
	var slot_idx: int = get_input_port_slot(port_idx)
	_inputs[slot_idx] = NULL_VALUE
	_update_output()
	
func _update_output() -> void:
	var new_output: int = _calculate_output()
	if new_output == _output: return
	_output = new_output
	
	_update_output_connections()
	
func _calculate_output() -> int:
	return 0

func _update_output_connections() -> void:
	var connections: Array[Dictionary] = _graph_edit.get_connection_list_from_output_port(self.name, _output_port_idx)
	for connection in connections:
		var graph_node_name: MyGraphNode = connection['node']
		var port_idx: int = connection['port']
		graph_node_name.update_input(port_idx, _output)
		
