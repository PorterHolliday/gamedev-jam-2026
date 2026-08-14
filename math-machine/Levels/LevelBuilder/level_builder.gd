class_name LevelBuilder
extends Node2D

const INPUT_MAX: int = 4
const OPERATION_MAX: int = 6
const OUTPUT_MAX: int = 4

@export var graph_canvas: GraphCanvas

@export_group("Location Groups")
@export var input_location_groups: Array[LocationGroup]
@export var operation_location_groups: Array[LocationGroup]
@export var output_location_groups: Array[LocationGroup]

func build(level_data: LevelData) -> void:
	if level_data == null:
		return
	
	_place_inputs(level_data)
	_place_operations(level_data)
	_place_outputs(level_data)

func _place_inputs(level_data: LevelData) -> void:
	var input_count: int = level_data.inputs.size()
	if input_count == 0:
		push_error('LevelData: ', level_data, ' has no inputs.')
		return
	if input_count > INPUT_MAX:
		push_error('LevelData: ', level_data, ' has more than ', INPUT_MAX, ' inputs.')
		return
		
	# Instantiate inputs
	for i in range(input_count):
		var input_data: GraphNodeData = level_data.inputs[i]
		var input: InputNode2 = NodeTypeRegistry.scene_for(input_data.type).instantiate()
		if NodeTypeRegistry.has_fixed_value(input_data.type):
			input.set('value', input_data.value)
		graph_canvas.add_child(input)
		var location_group: LocationGroup = input_location_groups[input_count - 1]
		var marker_2d: Marker2D = get_node(location_group.locations[i])
		input.global_position = marker_2d.global_position
		
func _place_operations(level_data: LevelData) -> void:
	var operation_count: int = level_data.operations.size()
	if operation_count == 0:
		push_error('LevelData: ', level_data, ' has no operations.')
		return
	if operation_count > OPERATION_MAX:
		push_error('LevelData: ', level_data, ' has more than ', OPERATION_MAX, ' operations.')
		return
		
	for i in range(operation_count):
		var operation_data: GraphNodeData = level_data.operations[i]
		if not operation_data:
			continue
		var operation: MyGraphNode = NodeTypeRegistry.scene_for(operation_data.type).instantiate()
		if NodeTypeRegistry.has_fixed_value(operation_data.type):
			operation.set('value', operation_data.value)
		graph_canvas.add_child(operation)
		var location_group: LocationGroup = operation_location_groups[operation_count - 1]
		var marker_2d: Marker2D = get_node(location_group.locations[i])
		operation.global_position = marker_2d.global_position
	
func _place_outputs(level_data: LevelData) -> void:
	var output_count: int = level_data.outputs.size()
	if output_count == 0:
		push_error('LevelData: ', level_data, ' has no outputs.')
		return
	if output_count > OUTPUT_MAX:
		push_error('LevelData: ', level_data, ' has more than ', OUTPUT_MAX, ' outputs.')
		return
	
	for i in range(output_count):
		var output_data: GraphNodeData = level_data.outputs[i]
		var output: OutputNode2 = NodeTypeRegistry.scene_for(output_data.type).instantiate()
		if NodeTypeRegistry.has_fixed_value(output_data.type):
			output.set('value', output_data.value)
		graph_canvas.add_child(output)
		var location_group: LocationGroup = output_location_groups[output_count - 1]
		var marker_2d: Marker2D = get_node(location_group.locations[i])
		output.global_position = marker_2d.global_position
