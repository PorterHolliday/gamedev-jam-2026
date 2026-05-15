class_name GraphNodePort
extends Marker2D

signal port_clicked
signal mouse_entered_port_area
signal mouse_exited_port_area

enum Type {
	INPUT,
	OUTPUT
}
@export var type: Type = Type.INPUT
@export var connection_color: Color = Color.WHITE

@onready var graph_node: Node2D = get_parent()
@onready var snap_area: Area2D = %Area2D
var _mouse_is_in_port_area: bool = false
var value: int

func _ready() -> void:
	snap_area.mouse_entered.connect(
		func(): 
			_mouse_is_in_port_area = true
			mouse_entered_port_area.emit())
	snap_area.mouse_exited.connect(
		func(): 
			_mouse_is_in_port_area = false
			mouse_exited_port_area.emit())
	
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and _mouse_is_in_port_area:
		port_clicked.emit()
		get_viewport().set_input_as_handled()
