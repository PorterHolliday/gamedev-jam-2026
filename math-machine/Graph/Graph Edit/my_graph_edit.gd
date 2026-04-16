class_name MyGraphEdit
extends GraphEdit

signal level_complete

const CONNECTION_GRAB_DISTANCE := 10.0

var _output_nodes: Array[OutputNode] = []

func _ready() -> void:
	right_disconnects = true
	connection_request.connect(_on_connection_request)
	disconnection_request.connect(_on_disconnection_request)
	
	for child in get_children():
		if child is OutputNode:
			_output_nodes.append(child)
			child.received_valid_output.connect(_check_level_complete)

func _gui_input(event: InputEvent) -> void:
	_handle_disconnection_on_right_click(event)
	
func _handle_disconnection_on_right_click(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var connection: Dictionary = get_closest_connection_at_point(event.position, CONNECTION_GRAB_DISTANCE)
		
		if connection.is_empty(): return
			
		disconnection_request.emit(
			connection.from_node,
			connection.from_port,
			connection.to_node,
			connection.to_port
		)
		get_viewport().set_input_as_handled()
	
func _on_connection_request(from_node_name: StringName, from_port: int, to_node_name: StringName, to_port: int) -> void:
	var from_node: MyGraphNode = get_node(NodePath(from_node_name))
	var to_node: MyGraphNode = get_node(NodePath(to_node_name))
	
	if to_node.is_input_connected(to_port): return
	if _is_loop_created(from_node, to_node): 
		print('loop created')
		return
	
	connect_node(from_node_name, from_port, to_node_name, to_port)
	to_node.update_input(to_port, from_node.output)
	
func _on_disconnection_request(from_node_name: StringName, from_port: int, to_node_name: StringName, to_port: int) -> void:
	var from_node: MyGraphNode = get_node(NodePath(from_node_name))
	var to_node: MyGraphNode = get_node(NodePath(to_node_name))
	
	disconnect_node(from_node_name, from_port, to_node_name, to_port)
	to_node.remove_input(to_port)
	
func _is_loop_created(search_for_node: MyGraphNode, next_node: MyGraphNode) -> bool:
	if next_node == search_for_node: return true
	if next_node is OutputNode: return false
	
	var output_connections = get_connection_list_from_output_port(next_node.name, 0)
	for connection in output_connections:
		print(connection['node'])
		if _is_loop_created(search_for_node, connection['node']): return true
	
	return false

func get_connection_list_from_output_port(node_name: StringName, port_idx: int) -> Array[Dictionary]:
	var node_connections: Array[Dictionary] = get_connection_list_from_node(node_name)
	var result: Array[Dictionary] = []
	for connection in node_connections:
		var dict = {}
		if connection["from_node"] == node_name and connection["from_port"] == port_idx:
			dict["node"] = get_node(NodePath(connection["to_node"]))
			dict["port"] = connection["to_port"]
			dict["type"] = "left"
			result.push_back(dict)
	return result

func _check_level_complete() -> void:
	for output in _output_nodes:
		if not output.is_satisfied:
			return
			
	level_complete.emit()
