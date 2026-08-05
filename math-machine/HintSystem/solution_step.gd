class_name SolutionStep
extends Resource

enum Type {
	STORE_VALUE,
	CONNECTION
}

@export var step_data: SolutionStepData
var type: Type = Type.CONNECTION:
	get():
		if step_data is ConnectionStepData:
			return Type.CONNECTION
		else:
			return Type.STORE_VALUE

## Accessor alias for `type`, per HintSystem naming convention.
func get_kind() -> Type:
	return type

## path is the SolutionPath this step belongs to. Needed (only for
## commutative-to_node CONNECTION steps) to disambiguate multiple steps
## that share the same from-node/to-node pair -- see
## _required_connection_count.
func is_satisfied(bindings: Dictionary, graph_canvas: GraphCanvas, path: SolutionPath) -> bool:
	match type:
		Type.STORE_VALUE:
			var node: MyGraphNode = bindings.get(Vector2i(step_data.STORE_TYPE, step_data.slot), null)
			if node == null:
				return false
			return node.value == step_data.value
		Type.CONNECTION:
			var from_node: MyGraphNode = bindings.get(Vector2i(step_data.from_type, step_data.from_slot))
			var to_node: MyGraphNode = bindings.get(Vector2i(step_data.to_type, step_data.to_slot))
			if from_node == null or to_node == null:
				return false
			if not _matches_value(from_node, step_data.from_value):
				return false
			if not _matches_value(to_node, step_data.to_value):
				return false

			if NodeTypeRegistry.is_commutative(step_data.to_type):
				# Port order doesn't matter, but a step still needs its OWN
				# distinct wire: if two steps both want a connection from
				# this same from_node into this same to_node (e.g. Store
				# wired into both of a Sum's inputs), the first is satisfied
				# by one live connection, the second only once a SECOND one
				# exists. Otherwise a single wire would satisfy both steps
				# at once and the hint system would skip the second.
				var required: int = _required_connection_count(path, bindings, from_node, to_node)
				var live: int = _live_connection_count(from_node, to_node, graph_canvas)
				return live >= required

			for connection in graph_canvas.connections:
				if connection.from_port == from_node.outputs[step_data.from_port] \
						and connection.to_port == to_node.inputs[step_data.to_port]:
					return true
			return false
	return false

## True if `node`'s value matches expected_value, or expected_value is
## ConnectionStepData.ANY_VALUE ("don't care"). Uses get() rather than
## direct property access so a misconfigured expected value on a node type
## with no `value` property (Sum, Subtract, ...) fails the check instead of
## crashing.
func _matches_value(node: MyGraphNode, expected_value: int) -> bool:
	if expected_value == ConnectionStepData.ANY_VALUE:
		return true
	return node.get("value") == expected_value

## This step's 1-based ordinal among every CONNECTION step in path (in list
## order, up to and including this step) that shares the same from_node,
## from_port, and to_node -- i.e. "this is the Nth request for a wire from
## from_node into to_node."
func _required_connection_count(path: SolutionPath, bindings: Dictionary, from_node: MyGraphNode, to_node: MyGraphNode) -> int:
	var count: int = 0
	for other_step in path.solution_steps:
		if other_step.get_kind() != Type.CONNECTION:
			continue
		var other_from: MyGraphNode = bindings.get(Vector2i(other_step.step_data.from_type, other_step.step_data.from_slot))
		var other_to: MyGraphNode = bindings.get(Vector2i(other_step.step_data.to_type, other_step.step_data.to_slot))
		if other_from != from_node or other_to != to_node:
			continue
		if other_step.step_data.from_port != step_data.from_port:
			continue
		count += 1
		if other_step == self:
			break
	return count

## Count of live connections from from_node's declared output into any
## input of to_node.
func _live_connection_count(from_node: MyGraphNode, to_node: MyGraphNode, graph_canvas: GraphCanvas) -> int:
	var count: int = 0
	for connection in graph_canvas.connections:
		if connection.from_port == from_node.outputs[step_data.from_port] \
				and to_node.inputs.has(connection.to_port):
			count += 1
	return count
