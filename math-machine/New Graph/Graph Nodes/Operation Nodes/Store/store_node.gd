class_name StoreNode
extends MyGraphNode2

var value: int = 0
@onready var value_label: Label = %ValueLabel

func _ready() -> void:
	super()
	outputs[0].value = 0

func update_input(port: GraphNodePort, new_value: int) -> void:
	super(port, new_value)
	if new_value != NULL_VALUE:
		value = new_value
	_disconnect_input()
	_update_value_label()
	
func _disconnect_input() -> void:
	var connection: = _graph_canvas.get_port_connections(inputs[0])[0]
	_graph_canvas.request_disconnection(connection, false)
	
func _calculate_outputs() -> Array[int]:
	return [value]
	
func _update_value_label() -> void:
	if value == NULL_VALUE:
		value_label.text = ''
	else:
		value_label.text = str(value)
