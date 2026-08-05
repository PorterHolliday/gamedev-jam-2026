extends Node

const script_registry: Dictionary[NodeType, Script] = {
	NodeType.INPUT: preload("res://Graph/Graph Nodes/Input Node/input_node.gd"),
	NodeType.OUTPUT: preload("res://Graph/Graph Nodes/Output Node/output_node.gd"),
	NodeType.ADD_VALUE: preload("res://Graph/Graph Nodes/Operation Nodes/Add Value/add_value_node.gd"),
	NodeType.SUM: preload("res://Graph/Graph Nodes/Operation Nodes/Sum/sum_node.gd"),
	NodeType.SUBTRACT: preload("res://Graph/Graph Nodes/Operation Nodes/Subtract/subtract_node.gd"),
	NodeType.STORE: preload("res://Graph/Graph Nodes/Operation Nodes/Store/store_node.gd"),
}

const scene_registry: Dictionary[NodeType, PackedScene] = {
	NodeType.INPUT: preload("res://Graph/Graph Nodes/Input Node/input_node.tscn"),
	NodeType.OUTPUT: preload("res://Graph/Graph Nodes/Output Node/output_node.tscn"),
	NodeType.ADD_VALUE: preload("res://Graph/Graph Nodes/Operation Nodes/Add Value/add_value_node.tscn"),
	NodeType.SUM: preload("res://Graph/Graph Nodes/Operation Nodes/Sum/sum_node.tscn"),
	NodeType.SUBTRACT: preload("res://Graph/Graph Nodes/Operation Nodes/Subtract/subtract_node.tscn"),
	NodeType.STORE: preload("res://Graph/Graph Nodes/Operation Nodes/Store/store_node.tscn"),
}

## Types whose multiple input ports are interchangeable (order doesn't
## affect the result), so a CONNECTION step's declared to_port shouldn't be
## enforced strictly for them -- see SolutionStep._matches_to_port.
const commutative_types: Array[NodeType] = [
	NodeType.SUM,
]

enum NodeType {
	INPUT,
	OUTPUT,
	ADD_VALUE,
	SUM,
	SUBTRACT,
	STORE,
	MULTIPLY,
	DIVIDE,
	INVERT,
	REVERSE,
	SPLIT,
	SUM_DIGITS,
	COMBINE
}

func is_commutative(type: NodeType) -> bool:
	return commutative_types.has(type)

func inherits(node: Node, type: NodeType) -> bool:
	if matches(node, type):
		return true
	
	var script: Script = node.get_script()
	var base_script: Script = script.get_base_script()
	# Check inheritance ancestors for type
	while base_script != null:
		if base_script == script_for(type):
			return true
		base_script = base_script.get_base_script()
	
	return false

func matches(node: Node, type: NodeType) -> bool:
	return node.get_script() == script_for(type)

func script_for(type: NodeType) -> Script:
	return script_registry.get(type)

func scene_for(type: NodeType) -> PackedScene:
	return scene_registry.get(type)
