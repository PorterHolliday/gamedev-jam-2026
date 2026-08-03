extends AnimationPlayer

const pointer_offset: Vector2 = Vector2(24, 8)

@export var graph_canvas: GraphCanvas
@export var add_value_node: AddValueNode
@export var pointer: TextureRect
@export var hand: TextureRect

var _has_disconnected: bool = false
var _has_dragged: bool = false
var _has_connected: bool = false

func _ready() -> void:
	play('disconnect_tutorial')
	graph_canvas.disconnection_occurred.connect(_on_disconnection_occurred)
	add_value_node._drag_control.drag_started.connect(_on_drag_started)
	graph_canvas.connection_occurred.connect(_on_connection_occurred)

func _on_disconnection_occurred() -> void:
	if _has_disconnected: return
	_has_disconnected = true
	pointer.hide()
	if not _has_dragged:
		play('drag_tutorial')
	elif not _has_connected:
		play('connect_tutorial')
	else:
		play('RESET')
	
func _on_drag_started() -> void:
	if _has_dragged: return
	_has_dragged = true
	hand.hide()
	if _has_disconnected:
		if not _has_connected:
			play('connect_tutorial')
		else:
			play('RESET')
	
func _on_connection_occurred() -> void:
	if _has_connected: return
	_has_connected = true
	if _has_disconnected and _has_dragged:
		play('RESET')

func _move_pointer_to_add_value_node_port() -> void:
	var port_position: Vector2 = add_value_node.inputs[0].global_position
	
	pause()
	
	var tween: Tween = get_tree().create_tween()
	tween.tween_property(pointer, 'global_position', port_position - pointer_offset, 1.0)
	await tween.finished
	
	await get_tree().create_timer(0.6).timeout
	
	seek(0)
	play()
