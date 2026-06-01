class_name SubtractNode
extends OperationNode2

func _calculate_outputs() -> Array[int]:
	if inputs[0].value == NULL_VALUE or inputs[1].value == NULL_VALUE:
		return [NULL_VALUE]
	return [inputs[0].value - inputs[1].value]
