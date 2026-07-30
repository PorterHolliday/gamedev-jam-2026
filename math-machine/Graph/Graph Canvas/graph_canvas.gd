class_name GraphCanvas
extends Node2D

const DISCONNECTION_DISTANCE: float = 40.0
const BEZIER_SAMPLES: float = 40
const LINE_WIDTH: float = 6.0
const BORDER_WIDTH: float = 6.0
const PREVIEW_COLOR: Color = Color(1.0, 1.0, 1.0, 0.8)
const BORDER_PREVIEW_COLOR: Color = Color(0.6, 0.6, 0.6, 0.6)
const SHADOW_OFFSET: Vector2 = Vector2(2, 2)
const SHADOW_COLOR: Color = Color(Color.BLACK, 0.64)

signal connection_occurred
signal disconnection_occurred
signal level_complete
var _output_nodes: Array[OutputNode2] = []

class Connection:
	var from_port: GraphNodePort
	var to_port: GraphNodePort
@export var init_connections: Array[ConnectionData] = []

@onready var double_click_detector: DoubleClickDetector = %DoubleClickDetector

var connections: Array[Connection] = []
var current_connection_start_port: GraphNodePort
var current_connection_end_port: GraphNodePort

var ports: Array[GraphNodePort] = []
var _level_completed: bool = false

func _ready() -> void:
	_connect_port_signals()
	
	double_click_detector.double_clicked.connect(_on_double_clicked)
	
	for connection_data in init_connections:
		var from_port: GraphNodePort = get_node(connection_data.from_node).outputs[connection_data.from_port]
		var to_port: GraphNodePort = get_node(connection_data.to_node).inputs[connection_data.to_port]
		request_connection(from_port, to_port, false)
	
	for child in get_children():
		if child is OutputNode2:
			_output_nodes.append(child)
			child.received_valid_output.connect(_check_level_complete.call_deferred)
			
func _process(_delta: float) -> void:
	queue_redraw()
	for port in ports:
		port.hide_hover_fill()
		if not current_connection_start_port:
			port.hide_bad_connection()
	if current_connection_start_port:
		current_connection_start_port.show_connected_fill()
	for connection in connections:
		connection.from_port.show_connected_fill()
		connection.to_port.show_connected_fill()

func _draw() -> void:
	var hovered_connection: Connection = _get_closest_connection_at_point(get_global_mouse_position(), DISCONNECTION_DISTANCE)
	for connection in connections:
		_draw_connection(connection, connection == hovered_connection)
	_draw_current_connection()
	
func get_port_connections(port: GraphNodePort) -> Array[Connection]:
	var port_connections: Array[Connection] = []
	for connection in connections:
		if connection.from_port == port or connection.to_port == port:
			port_connections.append(connection)
	
	return port_connections
	
func update_output_connections(port: GraphNodePort) -> void:
	var connections: Array[Connection] = get_port_connections(port)
	for connection in connections:
		connection.to_port.graph_node.update_input(connection.to_port, port.value)

func request_connection(port1: GraphNodePort, port2: GraphNodePort, play_sound: bool = true) -> bool:
	if not _can_connect_ports(port1, port2): return false
	
	var connection: Connection = Connection.new()
	if port1.type == GraphNodePort.Type.OUTPUT:
		connection.from_port = port1
		connection.to_port = port2
	else:
		connection.from_port = port2
		connection.to_port = port1
		
	if get_port_connections(connection.to_port).size() > 0:
		connections.erase(get_port_connections(connection.to_port)[0])
		
	connections.append(connection)
	
	if play_sound:
		AudioManager.play_connection_sfx()
	connection.to_port.graph_node.update_input(connection.to_port, connection.from_port.value)
	
	connection_occurred.emit()
	return true
	
func request_disconnection(connection: Connection, play_sound: bool = true) -> bool:
	if not connections.has(connection): return false
	
	connections.erase(connection)
	if play_sound:
		AudioManager.play_disconnection_sfx()
	connection.to_port.graph_node.remove_input(connection.to_port)
	
	disconnection_occurred.emit()
	return true

func play_level_complete_animation() -> void:	
	await get_tree().create_timer(0.3).timeout
	
	if _output_nodes.size() == 1: return
	
	for output_node in _output_nodes:
		output_node.play_level_complete_animation()
		await get_tree().create_timer(0.08).timeout
	await get_tree().create_timer(0.4).timeout
	
func _mouse_entered_port_area(port: GraphNodePort) -> void:
	if not current_connection_start_port: 
		port.show_hover_fill()
		return
	if _can_connect_ports(current_connection_start_port, port):
		port.show_hover_fill()
		current_connection_end_port = port
	elif port != current_connection_start_port:
		port.show_bad_connection()
	
func _mouse_exited_port_area(port: GraphNodePort) -> void:
	port.hide_hover_fill()
	port.hide_bad_connection()
	if not current_connection_start_port: return
	if port != current_connection_end_port: return
	current_connection_end_port = null
	
func _can_connect_ports(port1: GraphNodePort, port2: GraphNodePort) -> bool:
	if port1.type == port2.type: return false
	if port1.graph_node == port2.graph_node: return false
	
	for connection in connections:
		if (port1 == connection.from_port or port1 == connection.to_port)\
			and (port2 == connection.from_port or port2 == connection.to_port):
				return false
	
	if _is_loop_created(port1, port2): return false
	return true
	
func _is_loop_created(port1: GraphNodePort, port2: GraphNodePort) -> bool:
	if port1.type == GraphNodePort.Type.OUTPUT:
		return _loop_search(port1.graph_node, port2.graph_node)
	else:
		return _loop_search(port2.graph_node, port1.graph_node)
	
func _loop_search(search_for_node: MyGraphNode, next_node: MyGraphNode) -> bool:
	if next_node == search_for_node: return true
	if next_node is OutputNode2: return false
	
	for output in next_node.outputs:
		var output_connections: Array[Connection] = get_port_connections(output)
		for connection in output_connections:
			if _loop_search(search_for_node, connection.to_port.graph_node): return true
	
	return false
		
func _draw_connection(connection: Connection, is_hovered: bool) -> void:
	_draw_bezier(
			to_local(connection.from_port.global_position),
			to_local(connection.to_port.global_position),
			connection.from_port.connection_hover_color if is_hovered else connection.from_port.connection_color,
			connection.from_port.connection_border_color,
			true
		)
	
func _draw_current_connection() -> void:
	if current_connection_start_port != null:
		var start := to_local(current_connection_start_port.global_position)
		var end := to_local(current_connection_end_port.global_position) \
				if current_connection_end_port != null \
				else get_local_mouse_position()
		if current_connection_start_port.type == GraphNodePort.Type.OUTPUT:
			_draw_bezier(start, end, PREVIEW_COLOR, BORDER_PREVIEW_COLOR, false)
		else:
			_draw_bezier(end, start, PREVIEW_COLOR, BORDER_PREVIEW_COLOR, false)
			
func _draw_hovered_connection(connection: Connection) -> void:
	if not connection: return
	
	_draw_bezier(
			to_local(connection.from_port.global_position),
			to_local(connection.to_port.global_position),
			connection.from_port.connection_hover_color,
			connection.from_port.connection_border_color,
			true
		)
		
func _draw_bezier(from: Vector2, to: Vector2, color: Color, border_color: Color, draw_shadow: bool) -> void:
	var offset := Vector2(abs(to.x - from.x) * 0.5, 0.0)
	var p0 := from
	var p1 := from + offset
	var p2 := to - offset
	var p3 := to

	var points := PackedVector2Array()
	points.resize(BEZIER_SAMPLES + 1)
	var shadow_points := PackedVector2Array()
	shadow_points.resize(BEZIER_SAMPLES + 1)
	for i in range(BEZIER_SAMPLES + 1):
		var t := float(i) / float(BEZIER_SAMPLES)
		var u := 1.0 - t
		points[i] = u*u*u*p0 + 3.0*u*u*t*p1 + 3.0*u*t*t*p2 + t*t*t*p3
		shadow_points[i] = points[i] + SHADOW_OFFSET

	if draw_shadow:
		draw_polyline(shadow_points, SHADOW_COLOR, LINE_WIDTH + BORDER_WIDTH * 2.0, true)
	draw_polyline(points, border_color, LINE_WIDTH + BORDER_WIDTH * 2.0, true)
	draw_polyline(points, color, LINE_WIDTH, true)

func _port_released() -> void:
	if current_connection_start_port and current_connection_end_port:
		request_connection(current_connection_start_port, current_connection_end_port)
	current_connection_start_port = null
	current_connection_end_port = null
		
func _on_double_clicked(position: Vector2, _button_index: MouseButton) -> void:
	var connection: Connection = _get_closest_connection_at_point(position, DISCONNECTION_DISTANCE)
	if not connection: return
	request_disconnection(connection)
		
func _get_closest_connection_at_point(point: Vector2, max_distance: float) -> Connection:
	var closest: Connection = null
	var closest_dist := max_distance

	for conn in connections:
		var dist := _min_distance_to_bezier(point, conn)
		if dist < closest_dist:
			closest_dist = dist
			closest = conn

	return closest


func _min_distance_to_bezier(point: Vector2, conn: Connection, samples: int = 20) -> float:
	var min_dist := INF
	for i in samples:
		var t := float(i) / float(samples - 1)
		var curve_point := _sample_bezier(conn, t)
		min_dist = minf(min_dist, point.distance_to(curve_point))
	return min_dist

func _sample_bezier(conn: Connection, t: float) -> Vector2:
	var p0 := conn.from_port.global_position
	var p3 := conn.to_port.global_position
	var offset := Vector2(abs(p3.x - p0.x) * 0.5, 0.0)
	var p1 := p0 + offset
	var p2 := p3 - offset

	# Cubic Bezier
	var u := 1.0 - t
	return u*u*u*p0 + 3.0*u*u*t*p1 + 3.0*u*t*t*p2 + t*t*t*p3

func _check_level_complete() -> void:
	if _level_completed: return
	for output in _output_nodes:
		if not output.is_satisfied:
			return
	_level_completed = true
	level_complete.emit()
	
func _connect_port_signals() -> void:
	for child in get_children():
		if child is MyGraphNode:
			for grandchild in child.get_children():
				if grandchild is GraphNodePort:
					ports.append(grandchild)
					grandchild.port_clicked.connect(func(): _port_clicked(grandchild))
					grandchild.port_released.connect(_port_released)
					grandchild.mouse_entered_port_area.connect(func(): _mouse_entered_port_area(grandchild))
					grandchild.mouse_exited_port_area.connect(func(): _mouse_exited_port_area(grandchild))
					
func _port_clicked(port: GraphNodePort) -> void:
	# Disconnect if input already connected
	if port.type == GraphNodePort.Type.INPUT and get_port_connections(port).size() > 0:
		var connection: Connection = get_port_connections(port)[0]
		request_disconnection(connection, false)
		current_connection_start_port = connection.from_port
		return
	
	# Start connection from current port
	current_connection_start_port = port
