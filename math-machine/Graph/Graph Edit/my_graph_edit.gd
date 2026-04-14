class_name MyGraphEdit
extends GraphEdit

func _ready() -> void:
	right_disconnects = true
	connection_request.connect(_on_connection_request)
	disconnection_request.connect(_on_disconnection_request)
	
func _on_connection_request(from_node_name: StringName, from_port: int, to_node_name: StringName, to_port: int) -> void:
	var from_node: MyGraphNode = get_node(NodePath(from_node_name))
	var to_node: MyGraphNode = get_node(NodePath(to_node_name))
	
	to_node.update_input(to_port, from_node.output)
	
	connect_node(from_node_name, from_port, to_node_name, to_port)
	
func _on_disconnection_request(from_node_name: StringName, from_port: int, to_node_name: StringName, to_port: int) -> void:
	var from_node: MyGraphNode = get_node(NodePath(from_node_name))
	var to_node: MyGraphNode = get_node(NodePath(to_node_name))
	
	to_node.remove_input(to_port)
	
	disconnect_node(from_node_name, from_port, to_node_name, to_port)

func get_connection_list_from_output_port(node_name: StringName, port_idx: int) -> Array[Dictionary]:
	var connections: Array[Dictionary] = get_connection_list_from_node(node_name)
	var result: Array[Dictionary] = []
	for connection in connections:
		var dict = {}
		if connection["from_node"] == node_name and connection["from_port"] == port_idx:
			dict["node"] = get_node(NodePath(connection["to_node"]))
			dict["port"] = connection["to_port"]
			dict["type"] = "left"
			result.push_back(dict)
	return result
