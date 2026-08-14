class_name GraphCanvas
extends Node2D

const DISCONNECTION_DISTANCE: float = 40.0
const BEZIER_SAMPLES: float = 39
const LINE_WIDTH: float = 6.0
const BORDER_WIDTH: float = 6.0
const PREVIEW_COLOR: Color = Color(0.8, 0.8, 0.8, 0.8)
const BORDER_PREVIEW_COLOR: Color = Color(0.4, 0.4, 0.4, 0.6)
const VALID_CONNECTION_COLOR: Color = Color(1.0, 1.0, 1.0, 0.863)
const BORDER_VALID_CONNECTION_COLOR: Color = Color(0.6, 0.6, 0.6, 0.706)
const INVALID_CONNECTION_COLOR: Color = Color(1.0, 0.62, 0.62, 0.8)
const BORDER_INVALID_CONNECTION_COLOR: Color = Color(0.6, 0.318, 0.318, 0.6)
const TUTORIAL_CONNECTION_COLOR: Color = Color(1.0, 1.0, 1.0, 0.8)
const TUTORIAL_BORDER_CONNECTION_COLOR: Color = Color(1.0, 1.0, 1.0, 0.0)
const SHADOW_OFFSET: Vector2 = Vector2(2, 2)
const SHADOW_COLOR: Color = Color(Color.BLACK, 0.64)
const DASH_LENGTH: float = 24.0
const DASH_GAP: float = 24.0

signal connection_occurred
signal disconnection_occurred
signal level_complete
var nodes: Array[MyGraphNode] = []
var _output_nodes: Array[OutputNode2] = []

class Connection:
	var from_port: GraphNodePort
	var to_port: GraphNodePort
	func _init(_from: GraphNodePort = null, _to: GraphNodePort = null) -> void:
		from_port = _from
		to_port = _to
@export var tutorial_connection_data: Array[ConnectionData] = []

@onready var double_click_detector: DoubleClickDetector = %DoubleClickDetector
@onready var glow_panel: Panel = %GlowPanel

var connections: Array[Connection] = []
var tutorial_connections: Array[Connection] = []
var current_connection_start_port: GraphNodePort
var current_connection_end_port: GraphNodePort
var is_current_connection_valid: bool = false
var is_current_connection_invalid: bool = false

var ports: Array[GraphNodePort] = []
var hovered_port: GraphNodePort
var _level_completed: bool = false
var _hint_connections: Array[Connection] = []
var _hint_connection_alpha: float = HintVisuals.GLOW_ALPHA
var _hint_connection_tween: Tween

func start() -> void:
	_connect_port_signals()
	
	double_click_detector.double_clicked.connect(_on_double_clicked)
	
	for child in get_children():
		if child is MyGraphNode:
			nodes.append(child)
		if child is OutputNode2:
			_output_nodes.append(child)
			child.received_valid_output.connect(_check_level_complete.call_deferred)
	
	for connection_data in tutorial_connection_data:
		var from_port: GraphNodePort = nodes[connection_data.from_node_index].outputs[connection_data.from_port]
		var to_port: GraphNodePort = nodes[connection_data.to_node_index].inputs[connection_data.to_port]
		tutorial_connections.append(Connection.new(from_port, to_port))
			
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
	for connection in tutorial_connections:
		_draw_tutorial_connection(connection)
	for connection in connections:
		_draw_connection(connection, connection == hovered_connection)
	_draw_hint_connections()
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
		HapticManager.trigger_port_connect_haptic()
	connection.to_port.graph_node.update_input(connection.to_port, connection.from_port.value)
	
	connection.to_port.value_text_color = connection.from_port.value_panel_color
	connection.to_port.connected_color = connection.from_port.connection_color
	
	clear_hint_connection()
	connection_occurred.emit()
	return true
	
func request_disconnection(connection: Connection, play_sound: bool = true) -> bool:
	if not connections.has(connection): return false
	
	connections.erase(connection)
	if play_sound:
		HapticManager.trigger_port_disconnect_haptic()
		AudioManager.play_disconnection_sfx()
	connection.to_port.graph_node.remove_input(connection.to_port)
	
	clear_hint_connection()
	disconnection_occurred.emit()
	return true

## Sets the connection lines drawn as the current hint, glowing on a loop
## until the player changes the board or a new hint replaces them.
##
## port_pairs holds one [from_port, to_port] array per wire. A hint into a
## multi-input node is several wires at once, and they must replace the
## previous hint atomically and share a single tween -- drawn from one alpha
## they pulse together instead of drifting out of phase.
func set_hint_connections(port_pairs: Array[Array]) -> void:
	_hint_connections.clear()
	for pair in port_pairs:
		if pair.size() != 2:
			continue
		var connection := Connection.new()
		connection.from_port = pair[0]
		connection.to_port = pair[1]
		_hint_connections.append(connection)

	if _hint_connections.is_empty():
		clear_hint_connection()
		return
	_restart_hint_connection_pulse()

## Clears every hint connection line, if any.
func clear_hint_connection() -> void:
	_hint_connections.clear()
	if _hint_connection_tween:
		_hint_connection_tween.kill()
		_hint_connection_tween = null

func play_level_complete_animation() -> void:
	await get_tree().create_timer(0.3).timeout
	
	if _output_nodes.size() == 1: return
	
	for output_node in _output_nodes:
		output_node.play_level_complete_animation()
		await get_tree().create_timer(0.08).timeout
	await get_tree().create_timer(0.4).timeout
	
func _mouse_entered_port_area(port: GraphNodePort) -> void:
	hovered_port = port
	if not current_connection_start_port: 
		port.show_hover_fill()
		return
	if _can_connect_ports(current_connection_start_port, port):
		port.show_hover_fill()
		is_current_connection_valid = true
		current_connection_end_port = port
		_modulate_glow_panel(VALID_CONNECTION_COLOR)
		HapticManager.trigger_port_snap_haptic()
	elif port != current_connection_start_port:
		port.show_bad_connection()
		_modulate_glow_panel(INVALID_CONNECTION_COLOR)
		is_current_connection_invalid = true
	
func _mouse_exited_port_area(port: GraphNodePort) -> void:
	port.hide_hover_fill()
	port.hide_bad_connection()
	_modulate_glow_panel(Color(0.0, 0.0, 0.0, 0.0))
	is_current_connection_valid = false
	is_current_connection_invalid = false
	if not current_connection_start_port: return
	if port != current_connection_end_port: return
	current_connection_end_port = null
	
func _can_connect_ports(port1: GraphNodePort, port2: GraphNodePort) -> bool:
	return _get_connection_error(port1, port2) == ""
	
func _get_connection_error(port1: GraphNodePort, port2: GraphNodePort) -> String:
	if port1.type == port2.type:
		if port1.type == GraphNodePort.Type.INPUT:
			return "Both Empty"
		else:
			return "Both Full"
			
	if _is_loop_created(port1, port2):
		return "Creates Loop"
		
	return ""
	
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
		
func _draw_tutorial_connection(connection: Connection) -> void:
	_draw_dashed_bezier(
			to_local(connection.from_port.global_position),
			to_local(connection.to_port.global_position),
			TUTORIAL_CONNECTION_COLOR,
			TUTORIAL_BORDER_CONNECTION_COLOR,
			false
		)
	
func _draw_current_connection() -> void:
	if current_connection_start_port != null:
		var start := to_local(current_connection_start_port.global_position)
		var end := to_local(current_connection_end_port.global_position) \
				if current_connection_end_port != null \
				else get_local_mouse_position()
		var color: Color = PREVIEW_COLOR
		var border_color: Color = BORDER_PREVIEW_COLOR
		if is_current_connection_valid:
			color = VALID_CONNECTION_COLOR
			border_color = BORDER_VALID_CONNECTION_COLOR
		elif is_current_connection_invalid:
			color = INVALID_CONNECTION_COLOR
			border_color = BORDER_INVALID_CONNECTION_COLOR
		if current_connection_start_port.type == GraphNodePort.Type.OUTPUT:
			_draw_bezier(start, end, color, border_color, false)
		else:
			_draw_bezier(end, start, color, border_color, false)
			
func _draw_hovered_connection(connection: Connection) -> void:
	if not connection: return
	
	_draw_bezier(
			to_local(connection.from_port.global_position),
			to_local(connection.to_port.global_position),
			connection.from_port.connection_hover_color,
			connection.from_port.connection_border_color,
			true
		)
		
func _restart_hint_connection_pulse() -> void:
	if _hint_connection_tween:
		_hint_connection_tween.kill()
	_hint_connection_alpha = HintVisuals.GLOW_ALPHA
	_hint_connection_tween = create_tween()
	_hint_connection_tween.set_loops()
	_hint_connection_tween.tween_property(self, "_hint_connection_alpha", HintVisuals.DIM_ALPHA, HintVisuals.PULSE_DURATION)
	_hint_connection_tween.tween_property(self, "_hint_connection_alpha", HintVisuals.GLOW_ALPHA, HintVisuals.PULSE_DURATION)

func _draw_hint_connections() -> void:
	if _hint_connections.is_empty(): return
	var color: Color = HintVisuals.COLOR
	color.a = _hint_connection_alpha
	var border_color: Color = HintVisuals.BORDER_COLOR
	border_color.a = _hint_connection_alpha
	for connection in _hint_connections:
		_draw_bezier(
				to_local(connection.from_port.global_position),
				to_local(connection.to_port.global_position),
				color,
				border_color,
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
		
## Draws a dashed version of the same cubic bezier curve as _draw_bezier, with
## optional shadow and border. Dash segments are spaced evenly along the
## curve's arc length rather than its sample-point indices, so the middle of
## the curve doesn't look squished relative to the ends.
func _draw_dashed_bezier(from: Vector2, to: Vector2, color: Color, border_color: Color, draw_shadow: bool) -> void:
	var offset := Vector2(abs(to.x - from.x) * 0.5, 0.0)
	var p0 := from
	var p1 := from + offset
	var p2 := to - offset
	var p3 := to
	var points := PackedVector2Array()
	points.resize(BEZIER_SAMPLES + 1)
	for i in range(BEZIER_SAMPLES + 1):
		var t := float(i) / float(BEZIER_SAMPLES)
		var u := 1.0 - t
		points[i] = u*u*u*p0 + 3.0*u*u*t*p1 + 3.0*u*t*t*p2 + t*t*t*p3

	var dash_segments := _get_dashed_segments(points)

	for segment in dash_segments:
		if draw_shadow:
			var shadow_segment := PackedVector2Array()
			shadow_segment.resize(segment.size())
			for i in range(segment.size()):
				shadow_segment[i] = segment[i] + SHADOW_OFFSET
			draw_polyline(shadow_segment, SHADOW_COLOR, LINE_WIDTH + BORDER_WIDTH * 2.0, true)

		draw_polyline(segment, border_color, LINE_WIDTH + BORDER_WIDTH * 2.0, true)
		draw_polyline(segment, color, LINE_WIDTH, true)

## Splits a sampled polyline into evenly-spaced dash segments by walking
## along its cumulative arc length (rather than its point indices), using
## linear interpolation to place dash/gap boundaries exactly. This keeps
## dash length visually consistent even when the source points are not
## uniformly spaced, as with bezier sample points.
func _get_dashed_segments(points: PackedVector2Array) -> Array[PackedVector2Array]:
	var segments: Array[PackedVector2Array] = []
	if points.size() < 2:
		return segments

	var current_segment := PackedVector2Array()
	current_segment.append(points[0])
	var drawing := true
	var distance_into_phase := 0.0

	for i in range(1, points.size()):
		var segment_start := points[i - 1]
		var segment_end := points[i]
		var segment_length := segment_start.distance_to(segment_end)
		var traveled := 0.0

		while traveled < segment_length:
			var phase_length := DASH_LENGTH if drawing else DASH_GAP
			var remaining_in_phase := phase_length - distance_into_phase
			var remaining_in_segment := segment_length - traveled

			if remaining_in_phase <= remaining_in_segment:
				traveled += remaining_in_phase
				var point := segment_start.lerp(segment_end, traveled / segment_length)
				if drawing:
					current_segment.append(point)
					segments.append(current_segment)
					current_segment = PackedVector2Array()
				else:
					current_segment.append(point)
				drawing = not drawing
				distance_into_phase = 0.0
			else:
				traveled = segment_length
				distance_into_phase += remaining_in_segment
				if drawing:
					current_segment.append(segment_end)

	if drawing and current_segment.size() > 1:
		segments.append(current_segment)

	return segments

func _port_released() -> void:
	if current_connection_start_port and current_connection_end_port:
		request_connection(current_connection_start_port, current_connection_end_port)
	elif is_current_connection_invalid:
		var error: String = _get_connection_error(current_connection_start_port, hovered_port)
		hovered_port.show_error(error)
	_modulate_glow_panel(Color(0.0, 0.0, 0.0, 0.0))
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
	HapticManager.trigger_port_click_haptic()

func _modulate_glow_panel(color: Color) -> void:
	if OS.has_feature('web_android') or OS.has_feature('web_ios'):
		glow_panel.modulate = color
