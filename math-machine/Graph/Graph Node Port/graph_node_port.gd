class_name GraphNodePort
extends Marker2D

signal port_clicked
signal mouse_entered_port_area
signal mouse_exited_port_area

const NULL_VALUE: int = 9223372036854775807
enum Type {
	INPUT,
	OUTPUT
}
@export var type: Type = Type.INPUT
@export var connection_color: Color = Color.WHITE
@export var connection_border_color: Color = Color.BLACK

@onready var graph_node: MyGraphNode = get_parent()
@onready var snap_area: Area2D = %Area2D
@onready var panel_container: PanelContainer = %PanelContainer
@onready var value_label: Label = %Label
var _mouse_is_in_port_area: bool = false

var value: int = NULL_VALUE:
	set(new_val):
		value = new_val
		_update_value_label()

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

func _update_value_label() -> void:
	if value == NULL_VALUE:
		value_label.text = ''
		panel_container.hide()
	else:
		value_label.text = str(value)
		panel_container.show()
