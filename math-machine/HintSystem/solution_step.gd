class_name SolutionStep
extends Resource
## One step of a SolutionPath: either a connection the player must make, or
## a STORE_VALUE terminator marking the end of a phase.
##
## STORE_VALUE steps are structural only. They record which store slot
## latches and to what value so SolutionPath can derive its phase cursor;
## they are never evaluated for satisfaction and never surfaced as a hint.

# Enumerations
enum Type {
	STORE_VALUE,
	CONNECTION
}

# Exported variables
@export var step_data: SolutionStepData

# Regular variables
var type: Type = Type.CONNECTION:
	get():
		if step_data is ConnectionStepData:
			return Type.CONNECTION
		else:
			return Type.STORE_VALUE

# Public functions

## Accessor alias for `type`, per HintSystem naming convention.
func get_kind() -> Type:
	return type

## True if the current board already meets this step's requirement.
##
## phase_steps is the CONNECTION step list of the phase this step belongs
## to. It's needed (only for commutative-to_node CONNECTION steps) to
## disambiguate multiple steps in the SAME phase that share a
## from-node/to-node pair -- see _required_connection_count. Scoping it to
## one phase matters: the same wire legitimately recurs across phases, and
## counting across the whole path would inflate the required connection
## count and leave those steps permanently unsatisfied.
##
## STORE_VALUE steps always return false. A store's value is history, not a
## function of the current layout, so `node.value == step_data.value` can
## only ever detect the most recent latch -- treating that as progress is
## exactly the bug phasing exists to fix. Phase position is tracked by
## SolutionPath's cursor instead.
func is_satisfied(bindings: Dictionary, graph_canvas: GraphCanvas, phase_steps: Array[SolutionStep]) -> bool:
	match type:
		Type.STORE_VALUE:
			return false
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
				# distinct wire: if two steps in this phase both want a
				# connection from this same from_node into this same to_node
				# (e.g. Store wired into both of a Sum's inputs), the first is
				# satisfied by one live connection, the second only once a
				# SECOND one exists. Otherwise a single wire would satisfy both
				# steps at once and the hint system would skip the second.
				var required: int = _required_connection_count(phase_steps, bindings, from_node, to_node)
				var live: int = _live_connection_count(from_node, to_node, graph_canvas)
				return live >= required

			for connection in graph_canvas.connections:
				if connection.from_port == from_node.outputs[step_data.from_port] \
						and connection.to_port == to_node.inputs[step_data.to_port]:
					return true
			return false
	return false

# Private functions

## True if `node`'s value matches expected_value, or expected_value is
## ConnectionStepData.ANY_VALUE ("don't care"). Uses get() rather than
## direct property access so a misconfigured expected value on a node type
## with no `value` property (Sum, Subtract, ...) fails the check instead of
## crashing.
func _matches_value(node: MyGraphNode, expected_value: int) -> bool:
	if expected_value == ConnectionStepData.ANY_VALUE:
		return true
	return node.get("value") == expected_value

## This step's 1-based ordinal among every CONNECTION step in phase_steps
## (in list order, up to and including this step) that shares the same
## from_node, from_port, and to_node -- i.e. "this is the Nth request
## within this phase for a wire from from_node into to_node."
func _required_connection_count(phase_steps: Array[SolutionStep], bindings: Dictionary, from_node: MyGraphNode, to_node: MyGraphNode) -> int:
	var count: int = 0
	for other_step in phase_steps:
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
