class_name StoreNode
extends OperationNode

var value: int = NULL_VALUE
@onready var value_label: Label = %ValueLabel

func update_input(port: GraphNodePort, new_value: int) -> void:
	super(port, new_value)
	if new_value != NULL_VALUE:
		value = new_value
	_disconnect_input()
	_update_value_label()
	_update_outputs()
	
func _disconnect_input() -> void:
	var connection: = _graph_canvas.get_port_connections(inputs[0])[0]
	_graph_canvas.connections.erase(connection)
	inputs[0].value = NULL_VALUE
	
func _calculate_outputs() -> Array[int]:
	return [value]
	
func _update_value_label() -> void:
	if value == NULL_VALUE:
		value_label.text = '?'
	else:
		value_label.text = str(value)
