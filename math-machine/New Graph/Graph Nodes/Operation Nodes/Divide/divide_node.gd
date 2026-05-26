class_name DivideNode
extends MyGraphNode2

func _calculate_outputs() -> Array[int]:
	if inputs[0].value == NULL_VALUE or inputs[1].value == NULL_VALUE:
		return [NULL_VALUE, NULL_VALUE]
	if inputs[1].value == 0:
		return [NULL_VALUE, NULL_VALUE]
	return [inputs[0].value / inputs[1].value, inputs[0].value % inputs[1].value]
