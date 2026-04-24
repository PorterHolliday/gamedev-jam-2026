class_name MyGraphEdit
extends GraphEdit

signal level_complete
signal disconnection_occurred
signal connection_occurred

const CONNECTION_GRAB_DISTANCE := 10.0

var _output_nodes: Array[OutputNode] = []
@onready var animation_player: AnimationPlayer = %AnimationPlayer
@onready var connection_audio: AudioStreamPlayer = %ConnectionAudio
@onready var disconnection_audio: AudioStreamPlayer = %DisconnectionAudio
@onready var no_loops_audio: AudioStreamPlayer = %NoLoopsAudio

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
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		get_viewport().set_input_as_handled()
	
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
	
	if _is_loop_created(from_node, to_node): 
		animation_player.play('no_loops')
		no_loops_audio.play()
		return
	if get_connection_list_from_input_port(to_node_name, to_port).size() > 0: return
	
	if not to_node is StoreValueNode:
		connect_node(from_node_name, from_port, to_node_name, to_port)
		
	to_node.update_input(to_port, from_node.output)
	
	_play_connection_audio()
	
	connection_occurred.emit()
	
func _play_connection_audio() -> void:
	connection_audio.volume_db = randf_range(-10, 0)
	connection_audio.pitch_scale = randf_range(0.8, 1.2)
	connection_audio.play()
	
func _on_disconnection_request(from_node_name: StringName, from_port: int, to_node_name: StringName, to_port: int) -> void:
	var from_node: MyGraphNode = get_node(NodePath(from_node_name))
	var to_node: MyGraphNode = get_node(NodePath(to_node_name))
	
	disconnect_node(from_node_name, from_port, to_node_name, to_port)
	to_node.remove_input(to_port)
	
	_play_disconnection_audio()
	
	disconnection_occurred.emit()
	
func _play_disconnection_audio() -> void:
	disconnection_audio.volume_db = randf_range(-5, -2)
	disconnection_audio.pitch_scale = randf_range(0.8, 1.2)
	disconnection_audio.play(0.35)
	await get_tree().create_timer(0.18).timeout
	disconnection_audio.stop()
	
func _is_loop_created(search_for_node: MyGraphNode, next_node: MyGraphNode) -> bool:
	if next_node == search_for_node: return true
	if next_node is OutputNode: return false
	
	var output_connections = get_connection_list_from_output_port(next_node.name, 0)
	for connection in output_connections:
		if _is_loop_created(search_for_node, connection['node']): return true
	
	return false
	
func get_connection_list_from_input_port(node_name: StringName, port_idx: int) -> Array[Dictionary]:
	var node_connections: Array[Dictionary] = get_connection_list_from_node(node_name)
	var result: Array[Dictionary] = []
	for connection in node_connections:
		var dict = {}
		if connection["to_node"] == node_name and connection["to_port"] == port_idx:
			dict["node"] = get_node(NodePath(connection["from_node"]))
			dict["port"] = connection["from_port"]
			dict["type"] = "right"
			result.push_back(dict)
	return result

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
