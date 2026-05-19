class_name CombineNode
extends MyGraphNode2

func _calculate_outputs() -> Array[int]:
	if inputs[0].value == NULL_VALUE or inputs[1].value == NULL_VALUE:
		return [NULL_VALUE]
	
	var input1: int = inputs[0].value
	var input2: int = inputs[1].value
	var negative: bool = false
	if input1 < 0:
		negative = true
		input1 *= -1
	if input2 < 0:
		negative = true
		input2 *= -1
		
	var output: int = int(str(inputs[0].value) + str(inputs[1].value))
	if negative:
		output *= -1
	
	return [output]
