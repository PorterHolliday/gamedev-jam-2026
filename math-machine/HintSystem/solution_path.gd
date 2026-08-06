class_name SolutionPath
extends Resource
## A single valid solution to a level, expressed as an ordered sequence of
## phases.
##
## Every value in the graph is a pure function of the current wiring, with
## one exception: StoreNode latches its input and auto-severs, so a store's
## value is history rather than a function of the current layout. A path is
## therefore split into phases, each of which is a set of connections
## terminating in one store latch; the last phase terminates in level
## completion instead.
##
## Encoding: solution_steps is a flat array, and a STORE_VALUE step acts as
## a phase TERMINATOR sitting at the END of the phase it closes. Within a
## phase, ordering carries no gameplay meaning -- only the wiring at the
## instant of the latch has any effect -- so each phase is a declarative
## snapshot of every wire that must be live when the latch happens, not a
## delta against the previous phase.
##
## Progress is tracked by a phase cursor derived from per-phase required
## store state (see required_state), which is computed by liveness analysis
## over the path. No latch history is recorded, so the cursor is a pure
## function of current store values and cannot desynchronise.

# Exported variables
@export var solution_steps: Array[SolutionStep]

# Regular variables
## Per phase, its CONNECTION steps in authored order. Built lazily by
## _ensure_phases.
var _phase_connections: Array[Array] = []
## Per phase, its STORE_VALUE terminator, or null for the final phase.
var _phase_terminators: Array[SolutionStep] = []
## Per phase, store slot -> required value. Built lazily by
## _ensure_required_states, which needs the phases first.
var _required_states: Array[Dictionary] = []
var _phases_built: bool = false
var _required_states_built: bool = false

# Public functions

## Number of phases in this path. Always at least one: a path with no
## STORE_VALUE steps decomposes into a single final phase holding every
## step.
func get_phase_count() -> int:
	_ensure_phases()
	return _phase_connections.size()

## The CONNECTION steps of `phase_index`, in authored order. Returns an
## empty array for an out-of-range index rather than erroring, so a stale
## cursor can't crash a hint request.
func get_phase_connection_steps(phase_index: int) -> Array[SolutionStep]:
	_ensure_phases()
	var steps: Array[SolutionStep] = []
	if phase_index < 0 or phase_index >= _phase_connections.size():
		return steps
	steps.assign(_phase_connections[phase_index])
	return steps

## The STORE_VALUE step closing `phase_index`, or null for the final phase
## (and for an out-of-range index).
func get_phase_terminator(phase_index: int) -> SolutionStep:
	_ensure_phases()
	if phase_index < 0 or phase_index >= _phase_terminators.size():
		return null
	return _phase_terminators[phase_index]

## The last CONNECTION step of a non-final phase -- the wire whose making
## causes that phase's latch. Null for the final phase, and for a phase
## with no connection steps at all (which CR-6 validation flags).
func get_latch_connection(phase_index: int) -> SolutionStep:
	if get_phase_terminator(phase_index) == null:
		return null
	var connection_steps: Array = _phase_connections[phase_index]
	if connection_steps.is_empty():
		return null
	return connection_steps[connection_steps.size() - 1]

## Maps store slot -> the value that slot must currently hold for
## `phase_index` to be the player's position. A slot appears iff some
## earlier phase latched it AND that latched value is still live at this
## phase -- i.e. some phase from here onward reads the slot before any
## phase re-latches it. required_state(0) is always empty.
func required_state(phase_index: int) -> Dictionary:
	_ensure_required_states()
	if phase_index < 0 or phase_index >= _required_states.size():
		return {}
	return _required_states[phase_index]

## Resolves every {NodeType, slot} pair this path references to a live node
## in graph_canvas and reports how far along the path the resulting board
## sits.
##
## Bindings and cursor are maximised JOINTLY rather than in sequence: the
## cursor depends on which physical store is bound to which slot, and the
## quality of a binding is judged by the cursor it reaches. Scoring them
## separately would let a binding that happens to satisfy a stale wire
## outrank the binding the player is actually working with.
##
## Slots that can't be resolved (too few live instances of that type) are
## left out of the returned bindings rather than causing a crash -- see
## _live_instances_of_type.
func evaluate(graph_canvas: GraphCanvas) -> PathEvaluation:
	var slots_by_type: Dictionary = _collect_referenced_slots()

	# One Array[Dictionary] of candidate partial-bindings per type.
	var candidates_by_type: Array[Array] = []
	for type in slots_by_type:
		var slots: Array = slots_by_type[type]
		var live_instances: Array[MyGraphNode] = _live_instances_of_type(graph_canvas, type)

		if live_instances.size() < slots.size():
			push_error("SolutionPath: %d slot(s) reference NodeType %d but only %d live instance(s) exist" \
					% [slots.size(), type, live_instances.size()])
			continue

		candidates_by_type.append(_candidates_for_type(type, slots, live_instances))

	# Cross every type's candidates against each other -- a candidate isn't
	# scoreable until it's a full assignment, since CONNECTION steps span
	# two types at once.
	var best: PathEvaluation = PathEvaluation.new()
	for full_candidate in _combine_candidates(candidates_by_type):
		var cursor: int = _cursor_for_bindings(full_candidate)
		var score: Vector3i = _score_bindings(full_candidate, graph_canvas, cursor)
		if _is_better_score(score, best.score):
			best.bindings = full_candidate
			best.phase_index = cursor
			best.score = score

	return best

# Private functions

## Splits solution_steps into phases at each STORE_VALUE step, with the
## terminator belonging to the phase it CLOSES. The trailing run of
## CONNECTION steps is always pushed as the final phase, even when empty,
## so "the last phase has no terminator" holds unconditionally.
func _ensure_phases() -> void:
	if _phases_built:
		return
	_phases_built = true

	# Untyped inner arrays: Array[Array]'s element type is a bare Array, and
	# get_phase_connection_steps re-types each one on the way out.
	var current: Array = []
	for step in solution_steps:
		if step.get_kind() == SolutionStep.Type.CONNECTION:
			current.append(step)
		else:
			_phase_connections.append(current)
			_phase_terminators.append(step)
			current = []

	_phase_connections.append(current)
	_phase_terminators.append(null)

## Computes required_state for every phase. Results are a pure function of
## solution_steps, so this runs at most once per resource.
func _ensure_required_states() -> void:
	if _required_states_built:
		return
	_required_states_built = true
	_ensure_phases()

	var phase_count: int = _phase_connections.size()
	for phase_index in range(phase_count):
		var state: Dictionary = {}
		for slot in _latched_slots():
			if not _is_slot_live_at(slot, phase_index):
				continue
			var latch: SolutionStep = _last_latch_before(slot, phase_index)
			if latch == null:
				continue
			state[slot] = latch.step_data.value
		_required_states.append(state)

## Every store slot latched by some terminator on this path. Only these can
## ever appear in a required state -- a slot with no latch has no value to
## require.
func _latched_slots() -> Array[int]:
	var slots: Array[int] = []
	for terminator in _phase_terminators:
		if terminator == null:
			continue
		if not slots.has(terminator.step_data.slot):
			slots.append(terminator.step_data.slot)
	return slots

## The last terminator on `slot` among phases strictly before
## `phase_index`, or null if none has latched it yet.
func _last_latch_before(slot: int, phase_index: int) -> SolutionStep:
	var latest: SolutionStep = null
	for j in range(phase_index):
		var terminator: SolutionStep = _phase_terminators[j]
		if terminator != null and terminator.step_data.slot == slot:
			latest = terminator
	return latest

## True if `slot`'s currently-held value is still needed from `phase_index`
## onward: scanning phases forward, the first phase that either READS the
## slot (live) or RE-LATCHES it (dead) decides. Falling off the end means
## dead.
##
## The read check must precede the re-latch check WITHIN the same phase: a
## phase may legitimately read a store and latch over it, and in that case
## the old value is still required to enter the phase.
func _is_slot_live_at(slot: int, phase_index: int) -> bool:
	for j in range(phase_index, _phase_connections.size()):
		if _phase_reads_slot(j, slot):
			return true
		var terminator: SolutionStep = _phase_terminators[j]
		if terminator != null and terminator.step_data.slot == slot:
			return false
	return false

## True if any CONNECTION step in phase `phase_index` draws from the store
## in `slot`.
func _phase_reads_slot(phase_index: int, slot: int) -> bool:
	for step in _phase_connections[phase_index]:
		if step.step_data.from_type == NodeTypeRegistry.NodeType.STORE \
				and step.step_data.from_slot == slot:
			return true
	return false

## The highest phase index whose required_state is fully met by `bindings`.
## Phase 0 requires nothing, so this never fails to find an answer.
##
## Deliberately max-k rather than longest-matching-prefix: required_state is
## non-monotone by design (a phase that re-latches a store doesn't require
## that store's old value). This is sound because store state is the only
## hidden state in the game -- if the required stores hold the required
## values, the phase is genuinely reachable however the player got there.
## CR-6's duplicate-required-state check is what stops max-k silently
## skipping a phase's work.
func _cursor_for_bindings(bindings: Dictionary) -> int:
	var cursor: int = 0
	for phase_index in range(get_phase_count()):
		if _bindings_meet_required_state(bindings, required_state(phase_index)):
			cursor = phase_index
	return cursor

func _bindings_meet_required_state(bindings: Dictionary, state: Dictionary) -> bool:
	for slot in state:
		var node: MyGraphNode = bindings.get(Vector2i(NodeTypeRegistry.NodeType.STORE, slot))
		if node == null:
			return false
		if node.get("value") != state[slot]:
			return false
	return true

## Scores a candidate assignment for lexicographic comparison. Cursor
## dominates: a binding that gets the player further along the path is the
## binding they're working with, whatever stale wires happen to be live.
## Satisfied connections within the cursor phase break cursor ties, and
## total remaining work breaks those.
func _score_bindings(bindings: Dictionary, graph_canvas: GraphCanvas, cursor: int) -> Vector3i:
	var satisfied_in_phase: int = 0
	var unsatisfied_remaining: int = 0

	for phase_index in range(cursor, get_phase_count()):
		var phase_steps: Array[SolutionStep] = get_phase_connection_steps(phase_index)
		for step in phase_steps:
			if step.is_satisfied(bindings, graph_canvas, phase_steps):
				if phase_index == cursor:
					satisfied_in_phase += 1
			else:
				unsatisfied_remaining += 1

	return Vector3i(cursor, satisfied_in_phase, -unsatisfied_remaining)

## Strict lexicographic comparison, so ties still resolve to the earliest
## candidate (scene child order) as before.
func _is_better_score(score: Vector3i, best: Vector3i) -> bool:
	if score.x != best.x:
		return score.x > best.x
	if score.y != best.y:
		return score.y > best.y
	return score.z > best.z

func _collect_referenced_slots() -> Dictionary:
	var slots_by_type: Dictionary = {}
	for step in solution_steps:
		match step.get_kind():
			SolutionStep.Type.STORE_VALUE:
				_add_referenced_slot(slots_by_type, step.step_data.STORE_TYPE, step.step_data.slot)
			SolutionStep.Type.CONNECTION:
				_add_referenced_slot(slots_by_type, step.step_data.from_type, step.step_data.from_slot)
				_add_referenced_slot(slots_by_type, step.step_data.to_type, step.step_data.to_slot)
	return slots_by_type

func _add_referenced_slot(slots_by_type: Dictionary, type: NodeTypeRegistry.NodeType, slot: int) -> void:
	if not slots_by_type.has(type):
		slots_by_type[type] = []
	var slots: Array = slots_by_type[type]
	if not slots.has(slot):
		slots.append(slot)

func _live_instances_of_type(graph_canvas: GraphCanvas, type: NodeTypeRegistry.NodeType) -> Array[MyGraphNode]:
	var instances: Array[MyGraphNode] = []
	for child in graph_canvas.get_children():
		if child is MyGraphNode and NodeTypeRegistry.matches(child, type):
			instances.append(child)
	return instances

## One partial-bindings dict per injective assignment of `slots` onto
## `live_instances` (every permutation of size slots.size()), pruned by any
## known value requirements for types with a fixed, level-authored value
## (see _slot_value_requirements). Without this, a type with multiple live
## instances distinguished only by value (e.g. three Add Value nodes) can't
## be told apart by connection-based scoring alone until a live connection
## already proves which is which -- so on a fresh board, ties get broken
## arbitrarily (scene child order) instead of by the value the step data
## actually asked for, and the hint can point at the wrong instance.
##
## This pruning covers fixed_value_types only and deliberately does NOT
## extend to Store: a store slot has no single required value across a
## path, only a per-phase one. Cursor maximisation in evaluate() subsumes
## it -- a binding that puts the wrong physical store in a slot reaches a
## lower cursor and loses.
func _candidates_for_type(type: NodeTypeRegistry.NodeType, slots: Array, live_instances: Array[MyGraphNode]) -> Array[Dictionary]:
	var slot_value_requirements: Dictionary = _slot_value_requirements(type) if NodeTypeRegistry.has_fixed_value(type) else {}

	var candidates: Array[Dictionary] = []
	for assignment in _permutations(live_instances, slots.size()):
		if not _assignment_matches_value_requirements(assignment, slots, slot_value_requirements):
			continue
		var partial: Dictionary = {}
		for i in range(slots.size()):
			partial[Vector2i(type, slots[i])] = assignment[i]
		candidates.append(partial)

	if candidates.is_empty() and not slot_value_requirements.is_empty():
		push_error("SolutionPath: no live instance of NodeType %d matches the value(s) required for its slots" % type)

	return candidates

## True if every slot in `slots` that has a known value requirement is
## assigned (at the same index) a live instance whose value matches it.
## Slots with no known requirement (ANY_VALUE everywhere they're
## referenced) are unconstrained here.
func _assignment_matches_value_requirements(assignment: Array, slots: Array, slot_value_requirements: Dictionary) -> bool:
	for i in range(slots.size()):
		if not slot_value_requirements.has(slots[i]):
			continue
		if assignment[i].get("value") != slot_value_requirements[slots[i]]:
			return false
	return true

## Maps each slot of `type` to the value every step referencing it (as
## from_type/from_slot or to_type/to_slot) explicitly requires, skipping
## ConnectionStepData.ANY_VALUE ("don't care"). Assumes the existing
## convention that a given slot's required value is consistent everywhere
## it's referenced.
func _slot_value_requirements(type: NodeTypeRegistry.NodeType) -> Dictionary:
	var requirements: Dictionary = {}
	for step in solution_steps:
		if step.get_kind() != SolutionStep.Type.CONNECTION:
			continue
		if step.step_data.from_type == type and step.step_data.from_value != ConnectionStepData.ANY_VALUE:
			requirements[step.step_data.from_slot] = step.step_data.from_value
		if step.step_data.to_type == type and step.step_data.to_value != ConnectionStepData.ANY_VALUE:
			requirements[step.step_data.to_slot] = step.step_data.to_value
	return requirements

## All ordered picks of k distinct elements from pool. No built-in for this
## in GDScript; sizes here are always small per the level-design convention
## (2 slots x 2 instances, 3x3, etc.), so no memoization.
func _permutations(pool: Array, k: int) -> Array[Array]:
	if k == 0:
		return [[]]

	var result: Array[Array] = []
	for i in range(pool.size()):
		var remaining: Array = pool.duplicate()
		remaining.remove_at(i)
		for rest in _permutations(remaining, k - 1):
			var full: Array = [pool[i]]
			full.append_array(rest)
			result.append(full)
	return result

## Cartesian product of each type's candidate list, merged into full
## bindings dicts.
func _combine_candidates(candidates_by_type: Array[Array]) -> Array[Dictionary]:
	var combined: Array[Dictionary] = [{}]
	for candidates in candidates_by_type:
		var next_combined: Array[Dictionary] = []
		for partial_so_far in combined:
			for candidate in candidates:
				var merged: Dictionary = partial_so_far.duplicate()
				merged.merge(candidate)
				next_combined.append(merged)
		combined = next_combined
	return combined
