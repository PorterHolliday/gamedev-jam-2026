class_name SubtractOperation
extends OperationNode

func _ready() -> void:
	_input_count = 2
	super()
	
func _calculate_output() -> int:
	if _inputs[0] == NULL_VALUE or _inputs[1] == NULL_VALUE:
		return NULL_VALUE
	return _inputs[0] - _inputs[1]
