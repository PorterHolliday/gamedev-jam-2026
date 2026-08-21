@tool
class_name GraphNodePort
extends Marker2D

signal port_clicked
signal port_released
signal mouse_entered_port_area
signal mouse_exited_port_area

const ERROR_TIME: float = 1.5
const ERROR_FADE_DURATION: float = 0.2
const NULL_VALUE: int = 9223372036854775807
enum Type {
	INPUT,
	OUTPUT
}
@export var type: Type = Type.INPUT
@export var color: Color = Color.WHITE:
	set(new_val):
		color = new_val
		if panel:
			panel.modulate = color
@export var connection_color: Color = Color.WHITE
@export var connection_border_color: Color = Color.BLACK
@export var connection_hover_color: Color = Color.WHITE
@export var hover_color: Color = Color.BLACK
@export var connected_color: Color = Color.WHITE
@export var value_panel_color: Color = Color.WHITE:
	set(new_val):
		value_panel_color = new_val
		if value_panel_container:
			value_panel_container.self_modulate = value_panel_color
@export var value_text_color: Color = Color.WHITE:
	set(new_val):
		value_text_color = new_val
		if value_label:
			value_label.self_modulate = value_text_color

@onready var graph_node: MyGraphNode = get_parent()
@onready var panel: Panel = %Panel
@onready var snap_area: ClickableControl = %SnapArea
@onready var fill_panel: Panel = %FillPanel
@onready var bad_connection: Sprite2D = %BadConnection
@onready var value_container: DirectionalExpandContainer = %ValueContainer
@onready var value_panel_container: PanelContainer = %ValuePanelContainer
@onready var value_label: Label = %ValueLabel
@onready var error_container: DirectionalExpandContainer = %ErrorContainer
@onready var error_label: Label = %ErrorLabel

var _mouse_is_in_port_area: bool = false
var connected: bool = false

var value: int = NULL_VALUE:
	set(new_val):
		value = new_val
		_update_value_label()

func _ready() -> void:
	panel.modulate = color
	value_panel_container.self_modulate = value_panel_color
	value_label.self_modulate = value_text_color
	if Engine.is_editor_hint():
		return
	snap_area.mouse_entered.connect(_on_mouse_entered)
	snap_area.mouse_exited.connect(_on_mouse_exited)
	snap_area.mouse_clicked.connect(_on_mouse_clicked)
	snap_area.mouse_released.connect(_on_mouse_released)

func _update_value_label() -> void:
	if value == NULL_VALUE:
		value_label.text = ''
		value_container.hide()
	else:
		value_label.text = str(value)
		value_container.show()
		
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
	
func show_bad_connection() -> void:
	if not _mouse_is_in_port_area: return
	bad_connection.show()
	
func hide_bad_connection() -> void:
	bad_connection.hide()

func show_error(text: String) -> void:
	error_container.show()
	error_label.text = text
	await get_tree().create_timer(ERROR_TIME).timeout
	fade_out_error()
	
func fade_out_error() -> void:
	var tween: Tween = get_tree().create_tween()
	tween.tween_property(error_container, 'modulate', Color.TRANSPARENT, ERROR_FADE_DURATION)
	await tween.finished
	error_container.hide()
	error_container.modulate = Color.WHITE
	
func _on_mouse_clicked(mouse_button: MouseButton) -> void:
	if not mouse_button == MOUSE_BUTTON_LEFT:
		return
		
	port_clicked.emit()

func _on_mouse_released(mouse_button: MouseButton) -> void:
	if not mouse_button == MOUSE_BUTTON_LEFT:
		return
		
	port_released.emit()
