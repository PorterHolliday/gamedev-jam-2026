extends Node2D

const SPEED: float = 300.0
const WAIT_TIME: float = 0.5

@export var graph_canvas: GraphCanvas
@export var connection_data: ConnectionData

var from_port: GraphNodePort
var to_port: GraphNodePort

@onready var timer: Timer = %Timer

func _ready() -> void:
	if not get_parent().is_node_ready():
		await get_parent().ready
	_get_ports()
	global_position = from_port.global_position
	timer.start(WAIT_TIME)
	timer.timeout.connect(_on_timer_timeout)
	graph_canvas.connection_occurred.connect(_on_connection_occurred)

func _process(delta: float) -> void:
	if not timer.is_stopped():
		return
		
	var move_distance: float = SPEED * delta
	var total_distance: float = global_position.distance_to(to_port.global_position)
	if total_distance == 0:
		total_distance = 0.001
	if move_distance > total_distance:
		move_distance = total_distance
	var new_position: Vector2 = global_position.lerp(to_port.global_position, move_distance / total_distance)
	if global_position.distance_to(new_position) < 0.001:
		timer.start(WAIT_TIME)
	global_position = new_position
	
func _get_ports() -> void:
	var from_node: MyGraphNode = graph_canvas.nodes[connection_data.from_node_index]
	var to_node: MyGraphNode = graph_canvas.nodes[connection_data.to_node_index]
	from_port = from_node.outputs[connection_data.from_port]
	to_port = to_node.inputs[connection_data.to_port]
	
func _on_timer_timeout() -> void:
	if global_position == to_port.global_position:
		global_position = from_port.global_position
		timer.start(WAIT_TIME)

func _on_connection_occurred() -> void:
	queue_free()
