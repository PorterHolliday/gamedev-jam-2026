class_name SolutionPath
extends Resource

## A single valid solution to a level: an ordered list of steps (value
## stores followed by connections) plus the logic to resolve which live
## graph nodes satisfy this path's type/slot references.
##
## Convention: STORE_VALUE steps should be listed before CONNECTION steps.

@export var solution_steps: Array[SolutionStep]

## Resolves every {NodeType, slot} pair this path references to a live node
## in graph_canvas, picking the assignment that satisfies the most steps.
## Keyed by Vector2i(type, slot). Slots that can't be resolved (too few
## live instances of that type) are left out of the returned dictionary
## rather than causing a crash -- see _live_instances_of_type.
func resolve_bindings(graph_canvas: GraphCanvas) -> Dictionary:
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
	var best_bindings: Dictionary = {}
	var best_score: int = -1
	for full_candidate in _combine_candidates(candidates_by_type):
		var score: int = _score_bindings(full_candidate, graph_canvas)
		if score > best_score:
			best_score = score
			best_bindings = full_candidate

	return best_bindings

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
## `live_instances` (every permutation of size slots.size()).
func _candidates_for_type(type: NodeTypeRegistry.NodeType, slots: Array, live_instances: Array[MyGraphNode]) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for assignment in _permutations(live_instances, slots.size()):
		var partial: Dictionary = {}
		for i in range(slots.size()):
			partial[Vector2i(type, slots[i])] = assignment[i]
		candidates.append(partial)
	return candidates

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

func _score_bindings(bindings: Dictionary, graph_canvas: GraphCanvas) -> int:
	var score: int = 0
	for step in solution_steps:
		if step.is_satisfied(bindings, graph_canvas, self):
			score += 1
	return score
