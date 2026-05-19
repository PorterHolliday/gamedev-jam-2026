class_name SumDigitsNode
extends MyGraphNode2

func _calculate_outputs() -> Array[int]:
	if inputs[0].value == NULL_VALUE:
		return [NULL_VALUE]
		
	var input: int = inputs[0].value
	var negative: bool = false
	if input < 0:
		negative = true
		input *= -1
	var output: int = 0
	for c in str(input):
		output += int(c)
	if negative:
		output *= -1
	
	return [output]
