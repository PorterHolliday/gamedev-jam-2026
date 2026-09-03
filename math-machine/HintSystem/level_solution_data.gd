class_name LevelSolutionData
extends Resource
## Every known solution to a level, kept general-purpose rather than
## hint-specific: the hint system uses this to find the next unsatisfied
## step on the path the player is closest to, and challenge mode will use
## the same paths to determine which solutions a player has fully
## accomplished for a level.
##
## A path is fully accomplished when its cursor reaches the final phase and
## every connection in that phase is satisfied.

# Exported variables
@export var solution_paths: Array[SolutionPath]

# Regular variables
var _cached_path: SolutionPath
var _cached_bindings: Dictionary = {}
var _cached_phase_index: int = 0

# Public functions

## Picks the path that best matches the player's current progress by
## evaluating each one (jointly over bindings and phase cursor, see
## SolutionPath.evaluate) and taking the highest score, compared
## lexicographically as (cursor, satisfied connections in the cursor phase,
## -remaining unsatisfied connections).
##
## Cursor dominating means a path the player is deeper into always beats
## one they've merely made more scattered connections on. Ties go to the
## earliest path in `solution_paths`. Returns null only when there are no
## paths at all.
##
## Caches the winning path, its bindings and its cursor for reuse by
## get_next_hint()/get_hint_target() within the same hint request.
func get_current_path(graph_canvas: GraphCanvas) -> SolutionPath:
	_cached_path = null
	_cached_bindings = {}
	_cached_phase_index = 0

	var best_score: Vector3i = Vector3i(-1, -1, -1)
	for path in solution_paths:
		var evaluation: PathEvaluation = path.evaluate(graph_canvas)
		if not _is_better_score(evaluation.score, best_score):
			continue
		best_score = evaluation.score
		_cached_path = path
		_cached_bindings = evaluation.bindings
		_cached_phase_index = evaluation.phase_index

	return _cached_path

## The phase cursor of the path chosen by the most recent
## get_current_path() call.
func get_current_phase_index() -> int:
	return _cached_phase_index

## Returns the first unsatisfied CONNECTION step in the CURSOR PHASE of the
## current path (recomputing the current path, its bindings and its cursor
## first via get_current_path()), or null if every connection in that phase
## is already satisfied.
##
## Phases before and after the cursor are deliberately not searched. Work
## before the cursor is done; work after it is unreachable until this phase
## latches.
##
## Because the phase's latch connection is authored last (enforced by
## SolutionPathValidator), first-unsatisfied-in-order naturally withholds it
## until the rest of the phase is wired -- which is what stops the player
## being told to wire the store early and latch garbage into it.
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

	var phase_steps: Array[SolutionStep] = path.get_phase_connection_steps(_cached_phase_index)
	for step in phase_steps:
		if not step.is_satisfied(_cached_bindings, graph_canvas, phase_steps):
			return step
	return null

## The full hint for the current board: every unsatisfied step in the run
## of consecutive cursor-phase steps that share the hinted step's resolved
## `to` node.
##
## A hint for one input of a two-input node is misleading on its own -- the
## player wires it, the node still reads wrong because its other input is
## missing, and the hint looks like bad advice. Showing the whole run tells
## them what the node should be producing.
##
## Scanning forward only is sufficient: get_next_hint() returns the FIRST
## unsatisfied step, so anything earlier in the run is already satisfied and
## wouldn't be displayed anyway. Satisfied steps found mid-run are skipped
## for display but do NOT stop the scan, or a satisfied middle input would
## truncate the group.
##
## The run is well defined because the level generator requires a node's
## input connections to be contiguous within a phase; two consecutive steps
## into the same node otherwise have no meaning, since the second would
## immediately auto-sever the first.
func get_next_hint_group(graph_canvas: GraphCanvas) -> Array[SolutionStep]:
	var group: Array[SolutionStep] = []
	var first: SolutionStep = get_next_hint(graph_canvas)
	if first == null:
		return group

	var phase_steps: Array[SolutionStep] = _cached_path.get_phase_connection_steps(_cached_phase_index)
	var start: int = phase_steps.find(first)
	if start < 0:
		group.append(first)
		return group

	var run_to_node: MyGraphNode = _resolved_to_node(first)
	for i in range(start, phase_steps.size()):
		var step: SolutionStep = phase_steps[i]
		if _resolved_to_node(step) != run_to_node:
			break
		if step.is_satisfied(_cached_bindings, graph_canvas, phase_steps):
			continue
		group.append(step)
	return group

## Resolves a step's type/slot references to concrete nodes/ports using the
## bindings cached by the get_current_path() call inside get_next_hint() --
## a lookup, not a fresh resolve. Must be called for a step returned by the
## most recent get_next_hint() call on this same resource.
##
## Returns "nodes" and "ports" as before. When the cursor sits on a
## non-final phase, the result additionally carries "store_node" and
## "store_value": the store that phase's terminator latches and the value it
## latches into it. That's the goal the whole phase is building toward, and
## it's reported for EVERY step in the phase, not just the latch connection
## -- the presentation layer decides how much of it to show.
func get_hint_target(step: SolutionStep, graph_canvas: GraphCanvas) -> Dictionary:
	if step.get_kind() != SolutionStep.Type.CONNECTION:
		return {"nodes": [], "ports": []}

	var unclaimed: Array[GraphNodePort] = []
	var target: Dictionary = _connection_target(step, graph_canvas, unclaimed)
	target.merge(_phase_goal())
	return target

## Resolves a whole group from get_next_hint_group() in one call, so that
## ports are assigned across the group rather than per step.
##
## Returns "port_pairs" (an [from_port, to_port] array per hinted wire, in
## group order) plus the same "store_node"/"store_value" phase goal as
## get_hint_target(). Exactly one goal per hint, however many wires the
## group holds.
##
## Port assignment matters on a commutative target: two wires in one group
## must never be pointed at the same input port, so each member's chosen
## port is claimed and withheld from the rest. A group can never contain a
## latch connection -- Store has a single input port, so a run ending at a
## store always has length one.
func get_hint_group_target(steps: Array[SolutionStep], graph_canvas: GraphCanvas) -> Dictionary:
	var port_pairs: Array[Array] = []
	var claimed: Array[GraphNodePort] = []

	for step in steps:
		if step.get_kind() != SolutionStep.Type.CONNECTION:
			continue
		var target: Dictionary = _connection_target(step, graph_canvas, claimed)
		var ports: Array = target["ports"]
		if ports.size() != 2:
			continue
		claimed.append(ports[1])
		port_pairs.append([ports[0], ports[1]])

	var result: Dictionary = {"port_pairs": port_pairs}
	result.merge(_phase_goal())
	return result
	
## The index into solution_paths of the path chosen by the most recent
## get_current_path() call.
func get_current_path_index() -> int:
	return solution_paths.find(_cached_path)

## Where `step` sits in the current path's solution_steps array - the same
## index the editor shows next to each entry.
func get_step_index(step: SolutionStep) -> int:
	return _cached_path.solution_steps.find(step)

# Private functions

## The cursor phase's goal: the store its terminator latches and the value
## latched. Empty on the final phase, which has no terminator and so no
## goal store.
func _phase_goal() -> Dictionary:
	if _cached_path == null:
		return {}
	var terminator: SolutionStep = _cached_path.get_phase_terminator(_cached_phase_index)
	if terminator == null:
		return {}
	var store_node: MyGraphNode = _cached_bindings.get(Vector2i(terminator.step_data.STORE_TYPE, terminator.step_data.slot))
	if store_node == null:
		return {}
	return {"store_node": store_node, "store_value": terminator.step_data.value}

func _connection_target(step: SolutionStep, graph_canvas: GraphCanvas, claimed_ports: Array[GraphNodePort]) -> Dictionary:
	var from_node: MyGraphNode = _cached_bindings.get(Vector2i(step.step_data.from_type, step.step_data.from_slot))
	var to_node: MyGraphNode = _cached_bindings.get(Vector2i(step.step_data.to_type, step.step_data.to_slot))
	var nodes: Array[MyGraphNode] = []
	var ports: Array[GraphNodePort] = []
	if from_node:
		nodes.append(from_node)
		ports.append(from_node.outputs[step.step_data.from_port])
	if to_node:
		nodes.append(to_node)
		ports.append(_hint_to_port(to_node, step, graph_canvas, claimed_ports))
	return {"nodes": nodes, "ports": ports}

func _resolved_to_node(step: SolutionStep) -> MyGraphNode:
	if step.get_kind() != SolutionStep.Type.CONNECTION:
		return null
	return _cached_bindings.get(Vector2i(step.step_data.to_type, step.step_data.to_slot))

## Picks which input port on to_node the hint should point at. For
## non-commutative types this is always the step's declared to_port. For
## commutative types (Sum), to_port is only avoided if it's currently
## occupied by the specific connection satisfying a DIFFERENT step in this
## phase that also targets to_node -- i.e. a port another requirement has
## already correctly claimed -- or if another member of this same hint group
## has already been assigned it (claimed_ports). A port that's merely empty,
## or occupied by an incorrect/unrelated connection, is still this step's
## default -- the hint is meant to replace a wrong connection, not avoid it.
func _hint_to_port(to_node: MyGraphNode, step: SolutionStep, graph_canvas: GraphCanvas, claimed_ports: Array[GraphNodePort]) -> GraphNodePort:
	var default_port: GraphNodePort = to_node.inputs[step.step_data.to_port]
	if not NodeTypeRegistry.is_commutative(step.step_data.to_type):
		return default_port

	var reserved_ports: Array[GraphNodePort] = _reserved_ports(to_node, step, graph_canvas)
	for port in claimed_ports:
		if not reserved_ports.has(port):
			reserved_ports.append(port)

	if not reserved_ports.has(default_port):
		return default_port
	for port in to_node.inputs:
		if not reserved_ports.has(port):
			return port
	return default_port

## Ports on to_node currently occupied by the live connection that satisfies
## some OTHER CONNECTION step IN THE CURSOR PHASE also targeting to_node --
## ports a different requirement of this phase has already correctly
## claimed, and so shouldn't be suggested as this step's target.
##
## Scoped to the cursor phase because a reservation established three phases
## ago constrains nothing now, and would misdirect the hint on a commutative
## target.
func _reserved_ports(to_node: MyGraphNode, step: SolutionStep, graph_canvas: GraphCanvas) -> Array[GraphNodePort]:
	var reserved: Array[GraphNodePort] = []
	if _cached_path == null:
		return reserved

	var phase_steps: Array[SolutionStep] = _cached_path.get_phase_connection_steps(_cached_phase_index)
	for other_step in phase_steps:
		if other_step == step:
			continue

		var other_to_node: MyGraphNode = _cached_bindings.get(Vector2i(other_step.step_data.to_type, other_step.step_data.to_slot))
		if other_to_node != to_node:
			continue
		if not other_step.is_satisfied(_cached_bindings, graph_canvas, phase_steps):
			continue

		var other_from_node: MyGraphNode = _cached_bindings.get(Vector2i(other_step.step_data.from_type, other_step.step_data.from_slot))
		if other_from_node == null:
			continue

		for connection in graph_canvas.connections:
			if connection.from_port == other_from_node.outputs[other_step.step_data.from_port] \
					and to_node.inputs.has(connection.to_port):
				reserved.append(connection.to_port)

	return reserved

## Strict lexicographic comparison, so ties resolve to the earliest path in
## `solution_paths`.
func _is_better_score(score: Vector3i, best: Vector3i) -> bool:
	if score.x != best.x:
		return score.x > best.x
	if score.y != best.y:
		return score.y > best.y
	return score.z > best.z
