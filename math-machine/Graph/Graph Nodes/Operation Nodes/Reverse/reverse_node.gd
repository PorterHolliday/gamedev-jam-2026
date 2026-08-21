class_name ReverseNode
extends OperationNode

func _calculate_outputs() -> Array[int]:
	if inputs[0].value == NULL_VALUE:
		return [NULL_VALUE]
	
	var input: int = inputs[0].value
	
	var negative = false
	if input < 0:
		negative = true
		input *= -1
	
	var out_str: String = ''
	for c in str(input):
		out_str = c + out_str
	
	var output: int = int(out_str)
	if negative:
		output *= -1
		
	return [output]
