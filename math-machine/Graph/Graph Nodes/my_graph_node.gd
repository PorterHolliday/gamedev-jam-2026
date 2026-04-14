class_name MyGraphNode
extends GraphNode

@onready var _graph_edit: MyGraphEdit = get_parent()

const NULL_VALUE: int = 9223372036854775807
const OUTPUT_PORT_IDX: int = 0

var _inputs: Array[int] = []
var output: int = NULL_VALUE

func _ready() -> void:
	pass
	
func is_input_connected(port_idx: int) -> bool:
	var slot_idx: int = get_input_port_slot(port_idx)
	return _inputs[slot_idx] != NULL_VALUE

func add_input(port_idx: int, value: int) -> void:
	var slot_idx: int = get_input_port_slot(port_idx)
	_inputs[slot_idx] = value
	_update_output()
	
func remove_input(port_idx: int) -> void:
	var slot_idx: int = get_input_port_slot(port_idx)
	_inputs[slot_idx] = NULL_VALUE
	_update_output()
	
func _update_output() -> void:
	var new_output: int = _calculate_output()
	if new_output == output: return
	output = new_output
	
	_update_output_connections()
	
func _calculate_output() -> int:
	push_error(self, ' does not override _calculate_output()')
	return NULL_VALUE

func _update_output_connections() -> void:
	var connections: Array[Dictionary] = _graph_edit.get_connection_list_from_output_port(self.name, OUTPUT_PORT_IDX)
	for connection in connections:
		var graph_node_name: MyGraphNode = connection['node']
		var port_idx: int = connection['port']
		graph_node_name.update_input(port_idx, output)
		
