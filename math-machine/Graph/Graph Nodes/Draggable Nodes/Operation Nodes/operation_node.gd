class_name OperationNode
extends DraggableNode

@export var _input_labels: Array[Label] = []
@export var _output_label: Label

var _input_count: int = 0

func _ready() -> void:
	super()
			
	for i in range(_input_count):
		_inputs.append(NULL_VALUE)
		
func update_input(port_idx: int, value: int) -> void:
	super(port_idx, value)
	_update_input_label(port_idx)
	
func remove_input(port_idx: int) -> void:
	super(port_idx)
	_update_input_label(port_idx)
	
func _update_input_label(port_idx: int) -> void:
	var slot: int = _get_input_port_slot(port_idx)
	
	if _inputs[slot] == NULL_VALUE:
		_input_labels[slot].text = ''
	else:
		_input_labels[slot].text = str(_inputs[slot])

func _update_output() -> void:
	super()
	
	if output == NULL_VALUE:
		_output_label.text = ''
	else:
		_output_label.text = str(output)
