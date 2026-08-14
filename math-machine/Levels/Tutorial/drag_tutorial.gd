extends Node2D

const SPEED: float = 300.0
const WAIT_TIME: float = 0.5

@export var graph_canvas: GraphCanvas
@export var graph_node_index: int = 0
@export var final_position: Vector2 = Vector2.ZERO

@onready var timer: Timer = %Timer

var graph_node: OperationNode

func _ready() -> void:
	if not get_parent().is_node_ready():
		await get_parent().ready
	_get_graph_node()
	global_position = graph_node.global_position
	timer.start(WAIT_TIME)
	timer.timeout.connect(_on_timer_timeout)
	graph_node._drag_control.drag_started.connect(_on_graph_node_drag_started)

func _process(delta: float) -> void:
	if not timer.is_stopped():
		return
		
	var move_distance: float = SPEED * delta
	var total_distance: float = global_position.distance_to(final_position)
	if total_distance == 0:
		total_distance = 0.001
	if move_distance > total_distance:
		move_distance = total_distance
	var new_position: Vector2 = global_position.lerp(final_position, move_distance / total_distance)
	if global_position.distance_to(new_position) < 0.001:
		timer.start(WAIT_TIME)
	global_position = new_position
	
func _get_graph_node() -> void:
	graph_node = graph_canvas.nodes[graph_node_index]
	
func _on_timer_timeout() -> void:
	if global_position == final_position:
		global_position = graph_node.global_position
		timer.start(WAIT_TIME)

func _on_graph_node_drag_started() -> void:
	queue_free()
