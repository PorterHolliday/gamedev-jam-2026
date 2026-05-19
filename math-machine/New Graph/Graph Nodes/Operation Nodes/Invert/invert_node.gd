class_name InvertNode
extends MyGraphNode2

func _calculate_outputs() -> Array[int]:
	if inputs[0].value == NULL_VALUE:
		return [NULL_VALUE]
	
	return [-inputs[0].value]
