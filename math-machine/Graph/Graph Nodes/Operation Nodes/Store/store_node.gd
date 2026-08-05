class_name StoreNode
extends OperationNode

var value: int = NULL_VALUE
var _hint_tween: Tween
@onready var value_label: Label = %ValueLabel

func update_input(port: GraphNodePort, new_value: int) -> void:
	super(port, new_value)
	if new_value != NULL_VALUE:
		value = new_value
	_disconnect_input()
	_update_value_label()
	_update_outputs()

## Pulses the target value in gold for HintVisuals.STORE_VALUE_PULSE_COUNT
## slow beats, then reverts to whatever the node's real state is -- never
## claims a value is stored that isn't.
func show_hint_value(target_value: int) -> void:
	if _hint_tween:
		_hint_tween.kill()

	value_label.text = str(target_value)
	value_label.modulate = HintVisuals.COLOR

	_hint_tween = create_tween()
	_hint_tween.set_loops(HintVisuals.STORE_VALUE_PULSE_COUNT)
	_hint_tween.tween_property(value_label, "modulate:a", HintVisuals.DIM_ALPHA, HintVisuals.PULSE_DURATION)
	_hint_tween.tween_property(value_label, "modulate:a", HintVisuals.GLOW_ALPHA, HintVisuals.PULSE_DURATION)
	_hint_tween.finished.connect(_update_value_label, CONNECT_ONE_SHOT)

func _disconnect_input() -> void:
	var connection: = _graph_canvas.get_port_connections(inputs[0])[0]
	_graph_canvas.connections.erase(connection)
	inputs[0].value = NULL_VALUE

func _calculate_outputs() -> Array[int]:
	return [value]

func _update_value_label() -> void:
	if _hint_tween:
		_hint_tween.kill()
		_hint_tween = null
	value_label.modulate = Color.WHITE
	if value == NULL_VALUE:
		value_label.text = '?'
	else:
		value_label.text = str(value)
