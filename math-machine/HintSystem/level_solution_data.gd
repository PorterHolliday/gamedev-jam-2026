class_name LevelSolutionData
extends Resource

## Every known solution to a level, kept general-purpose rather than
## hint-specific: the hint system uses this to find the next unsatisfied
## step on the path the player is closest to, and challenge mode will use
## the same paths to determine which solutions a player has fully
## accomplished for a level.

@export var solution_paths: Array[SolutionPath]

var _cached_path: SolutionPath
var _cached_bindings: Dictionary = {}

## Picks the path that best matches the player's current progress:
##  1. Among paths whose STORE_VALUE steps are all satisfied (or have none),
##     the one with the most satisfied CONNECTION steps wins.
##  2. Otherwise, among paths with some (not all) STORE_VALUE steps
##     satisfied, the one with the most satisfied STORE_VALUE steps wins.
##  3. Otherwise, defaults to solution_paths[0].
## Ties go to the earliest path in `solution_paths`. Caches the winning
## path and its resolved bindings for reuse by get_hint_target() within the
## same hint request.
func get_current_path(graph_canvas: GraphCanvas) -> SolutionPath:
	if solution_paths.is_empty():
		_cached_path = null
		_cached_bindings = {}
		return null

	var bindings_by_path: Dictionary = {}
	var tier1_best: SolutionPath = null
	var tier1_best_score: int = -1
	var tier2_best: SolutionPath = null
	var tier2_best_score: int = -1

	for path in solution_paths:
		var bindings: Dictionary = path.resolve_bindings(graph_canvas)
		bindings_by_path[path] = bindings

		var store_steps: Array[SolutionStep] = _steps_of_kind(path, SolutionStep.Type.STORE_VALUE)
		var connection_steps: Array[SolutionStep] = _steps_of_kind(path, SolutionStep.Type.CONNECTION)
		var satisfied_store_count: int = _count_satisfied(store_steps, bindings, graph_canvas, path)

		if store_steps.is_empty() or satisfied_store_count == store_steps.size():
			var satisfied_connection_count: int = _count_satisfied(connection_steps, bindings, graph_canvas, path)
			if satisfied_connection_count > tier1_best_score:
				tier1_best_score = satisfied_connection_count
				tier1_best = path
		elif satisfied_store_count > 0:
			if satisfied_store_count > tier2_best_score:
				tier2_best_score = satisfied_store_count
				tier2_best = path

	var winner: SolutionPath = tier1_best
	if winner == null:
		winner = tier2_best
	if winner == null:
		winner = solution_paths[0]

	_cached_path = winner
	_cached_bindings = bindings_by_path.get(winner, {})
	return winner

## Returns the first unsatisfied step in the current path (recomputing the
## current path and its bindings first via get_current_path()), or null if
## every step is already satisfied.
##
## Recomputes on every call rather than trusting a long-lived cache, since
## bindings can go stale the moment the player makes or breaks a connection
## between hint requests. Call this once per hint request, then
## get_hint_target() for the same step immediately after -- that pairing is
## the only scope the cache is meant to survive.
func get_next_hint(graph_canvas: GraphCanvas) -> SolutionStep:
	var path: SolutionPath = get_current_path(graph_canvas)
	if path == null:
		return null

	for step in path.solution_steps:
		if not step.is_satisfied(_cached_bindings, graph_canvas, path):
			return step
	return null

## Resolves a step's type/slot references to concrete nodes/ports using the
## bindings cached by the get_current_path() call inside get_next_hint() --
## a lookup, not a fresh resolve. Must be called for a step returned by the
## most recent get_next_hint() call on this same resource.
func get_hint_target(step: SolutionStep, graph_canvas: GraphCanvas) -> Dictionary:
	match step.get_kind():
		SolutionStep.Type.STORE_VALUE:
			var node: MyGraphNode = _cached_bindings.get(Vector2i(step.step_data.STORE_TYPE, step.step_data.slot))
			return {"nodes": [node] if node else [], "ports": []}
		SolutionStep.Type.CONNECTION:
			var from_node: MyGraphNode = _cached_bindings.get(Vector2i(step.step_data.from_type, step.step_data.from_slot))
			var to_node: MyGraphNode = _cached_bindings.get(Vector2i(step.step_data.to_type, step.step_data.to_slot))
			var nodes: Array[MyGraphNode] = []
			var ports: Array[GraphNodePort] = []
			if from_node:
				nodes.append(from_node)
				ports.append(from_node.outputs[step.step_data.from_port])
			if to_node:
				nodes.append(to_node)
				ports.append(_hint_to_port(to_node, step, graph_canvas))
			return {"nodes": nodes, "ports": ports}
	return {"nodes": [], "ports": []}

## Picks which input port on to_node the hint should point at. For
## non-commutative types this is always the step's declared to_port. For
## commutative types (Sum), to_port is only avoided if it's currently
## occupied by the specific connection satisfying a DIFFERENT step in this
## path that also targets to_node -- i.e. a port another requirement has
## already correctly claimed. A port that's merely empty, or occupied by an
## incorrect/unrelated connection, is still this step's default -- the hint
## is meant to replace a wrong connection, not avoid it.
func _hint_to_port(to_node: MyGraphNode, step: SolutionStep, graph_canvas: GraphCanvas) -> GraphNodePort:
	var default_port: GraphNodePort = to_node.inputs[step.step_data.to_port]
	if not NodeTypeRegistry.is_commutative(step.step_data.to_type):
		return default_port

	var reserved_ports: Array[GraphNodePort] = _reserved_ports(to_node, step, graph_canvas)
	if not reserved_ports.has(default_port):
		return default_port
	for port in to_node.inputs:
		if not reserved_ports.has(port):
			return port
	return default_port

## Ports on to_node currently occupied by the live connection that satisfies
## some OTHER CONNECTION step in the current path also targeting to_node --
## ports a different requirement has already correctly claimed, and so
## shouldn't be suggested as this step's target.
func _reserved_ports(to_node: MyGraphNode, step: SolutionStep, graph_canvas: GraphCanvas) -> Array[GraphNodePort]:
	var reserved: Array[GraphNodePort] = []
	if _cached_path == null:
		return reserved

	for other_step in _cached_path.solution_steps:
		if other_step == step:
			continue
		if other_step.get_kind() != SolutionStep.Type.CONNECTION:
			continue

		var other_to_node: MyGraphNode = _cached_bindings.get(Vector2i(other_step.step_data.to_type, other_step.step_data.to_slot))
		if other_to_node != to_node:
			continue
		if not other_step.is_satisfied(_cached_bindings, graph_canvas, _cached_path):
			continue

		var other_from_node: MyGraphNode = _cached_bindings.get(Vector2i(other_step.step_data.from_type, other_step.step_data.from_slot))
		if other_from_node == null:
			continue

		for connection in graph_canvas.connections:
			if connection.from_port == other_from_node.outputs[other_step.step_data.from_port] \
					and to_node.inputs.has(connection.to_port):
				reserved.append(connection.to_port)

	return reserved

func _steps_of_kind(path: SolutionPath, kind: SolutionStep.Type) -> Array[SolutionStep]:
	var steps: Array[SolutionStep] = []
	for step in path.solution_steps:
		if step.get_kind() == kind:
			steps.append(step)
	return steps

func _count_satisfied(steps: Array[SolutionStep], bindings: Dictionary, graph_canvas: GraphCanvas, path: SolutionPath) -> int:
	var count: int = 0
	for step in steps:
		if step.is_satisfied(bindings, graph_canvas, path):
			count += 1
	return count
