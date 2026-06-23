class_name SplitNode
extends OperationNode

func _calculate_outputs() -> Array[int]:
	if inputs[0].value == NULL_VALUE:
		return [NULL_VALUE, NULL_VALUE]
	
	var input: int = inputs[0].value
	var negative: bool = false
	if input < 0:
		negative = true
		input *= -1
	var first: int = int(str(input).substr(0, 1))
	var rest: int = int(str(input).substr(1))
	if not rest:
		rest = 0
	if negative:
		first *= -1
	return [first, rest]
