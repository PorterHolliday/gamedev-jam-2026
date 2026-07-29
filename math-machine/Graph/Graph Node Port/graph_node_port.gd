class_name GraphNodePort
extends Marker2D

signal port_clicked
signal port_released
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
@export var connection_hover_color: Color = Color.WHITE
@export var hover_color: Color = Color.BLACK
@export var connected_color: Color = Color.DIM_GRAY

@onready var graph_node: MyGraphNode = get_parent()
@onready var snap_area: ClickableControl = %SnapArea
@onready var fill_panel: Panel = %FillPanel
@onready var panel_container: PanelContainer = %PanelContainer
@onready var value_label: Label = %Label
var _mouse_is_in_port_area: bool = false
var connected: bool = false

var value: int = NULL_VALUE:
	set(new_val):
		value = new_val
		_update_value_label()

func _ready() -> void:
	snap_area.mouse_entered.connect(_on_mouse_entered)
	snap_area.mouse_exited.connect(_on_mouse_exited)
	snap_area.mouse_clicked.connect(func(mouse_button):
		port_clicked.emit())
	snap_area.mouse_released.connect(func(mouse_button):
		port_released.emit())

func _update_value_label() -> void:
	if value == NULL_VALUE:
		value_label.text = ''
		panel_container.hide()
	else:
		value_label.text = str(value)
		panel_container.show()
		
func _on_mouse_entered() -> void:
	_mouse_is_in_port_area = true
	mouse_entered_port_area.emit()
	
func _on_mouse_exited() -> void:
	_mouse_is_in_port_area = false
	mouse_exited_port_area.emit()
	
func show_hover_fill() -> void:
	if not _mouse_is_in_port_area: return
	fill_panel.show()
	fill_panel.modulate = hover_color
	
func hide_hover_fill() -> void:
	if _mouse_is_in_port_area: return
	fill_panel.hide()

func show_connected_fill() -> void:
	if _mouse_is_in_port_area: return
	fill_panel.show()
	fill_panel.modulate = connected_color
