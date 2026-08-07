class_name SolutionPathValidator
extends RefCounted
## Authoring-time checks on phased solution data, callable from a test or an
## editor tool.
##
## The flat solution_steps encoding makes phase structure a CONVENTION
## rather than a type -- nothing in the resource format stops a terminator
## landing in the wrong place, or a latch nobody ever reads. The invariants
## the runtime rests on therefore have to be checked explicitly, and this is
## where. Nothing here runs during play.
##
## Every violation is reported through push_error and counted; validate()
## returns the number found, so a caller can assert zero.

# Public static functions

## Runs every check over `level_data`'s solution paths and returns the
## number of violations found. `context` is prefixed to each message so a
## bulk run can say which file failed.
static func validate(level_data: LevelData, context: String = "") -> int:
	if level_data == null:
		push_error("%s: no LevelData to validate" % _label(context))
		return 1
	if level_data.level_solution_data == null:
		return 0

	var available: Dictionary = _available_slot_counts(level_data)
	var violations: int = 0
	var paths: Array[SolutionPath] = level_data.level_solution_data.solution_paths
	for path_index in range(paths.size()):
		violations += validate_path(paths[path_index], available, "%s path %d" % [_label(context), path_index])
	return violations

## Runs every check over a single path. `available_slot_counts` maps
## NodeTypeRegistry.NodeType -> how many nodes of that type the level
## builds, which is what bounds a legal slot index.
static func validate_path(path: SolutionPath, available_slot_counts: Dictionary, context: String) -> int:
	var violations: int = 0
	violations += _check_latch_connection_last(path, context)
	violations += _check_no_duplicate_required_states(path, context)
	violations += _check_no_dead_latches(path, context)
	violations += _check_no_empty_phases(path, context)
	violations += _check_referential_integrity(path, available_slot_counts, context)
	return violations

# Private static functions

## Check 1. In every non-final phase the LAST connection step must be the
## one that wires the phase's own store. Anything else and the hint system,
## which offers the phase's steps in authored order, will invite the player
## to wire the store before its inputs are ready -- latching garbage.
static func _check_latch_connection_last(path: SolutionPath, context: String) -> int:
	var violations: int = 0
	for phase_index in range(path.get_phase_count()):
		var terminator: SolutionStep = path.get_phase_terminator(phase_index)
		if terminator == null:
			continue
		var latch: SolutionStep = path.get_latch_connection(phase_index)
		if latch == null:
			continue
		if latch.step_data.to_type != NodeTypeRegistry.NodeType.STORE:
			push_error("%s phase %d: last connection targets NodeType %d, not a Store" \
					% [context, phase_index, latch.step_data.to_type])
			violations += 1
		elif latch.step_data.to_slot != terminator.step_data.slot:
			push_error("%s phase %d: last connection targets Store slot %d but the terminator latches slot %d" \
					% [context, phase_index, latch.step_data.to_slot, terminator.step_data.slot])
			violations += 1
	return violations

## Check 2. Two phases with identical required states are indistinguishable
## to the cursor, and since the cursor takes the HIGHEST matching phase the
## earlier one's work is silently skipped. Canonical authoring can't produce
## this -- a phase's latch shows up in the next phase's required state
## whenever it's ever read -- so a hit here means a dead latch or a
## mis-ordered path.
static func _check_no_duplicate_required_states(path: SolutionPath, context: String) -> int:
	var violations: int = 0
	var seen: Array[String] = []
	for phase_index in range(path.get_phase_count()):
		var key: String = _required_state_key(path.required_state(phase_index))
		var earlier_index: int = seen.find(key)
		if earlier_index >= 0:
			push_error("%s phase %d: required state {%s} duplicates phase %d, so the cursor will skip phase %d's work" \
					% [context, phase_index, key, earlier_index, earlier_index])
			violations += 1
		seen.append(key)
	return violations

## Canonical string form of a required state, so two states compare equal
## iff they hold the same slot/value pairs. Compared as strings rather than
## with Dictionary ==, whose deep-vs-reference semantics aren't worth
## resting a correctness check on -- and each phase's state is a separately
## built Dictionary, so a reference comparison would silently never fire.
static func _required_state_key(state: Dictionary) -> String:
	var slots: Array = state.keys()
	slots.sort()
	var parts: PackedStringArray = PackedStringArray()
	for slot in slots:
		parts.append("%d:%d" % [slot, state[slot]])
	return ", ".join(parts)

## Check 3. Every terminator's slot must be read by a later phase, or be
## part of the final phase's required state. A latch nothing ever consumes
## is wasted authoring and shouldn't have been emitted.
static func _check_no_dead_latches(path: SolutionPath, context: String) -> int:
	var violations: int = 0
	var phase_count: int = path.get_phase_count()
	for phase_index in range(phase_count):
		var terminator: SolutionStep = path.get_phase_terminator(phase_index)
		if terminator == null:
			continue
		if _slot_read_after(path, terminator.step_data.slot, phase_index + 1):
			continue
		push_error("%s phase %d: latches Store slot %d, which no later phase ever reads" \
				% [context, phase_index, terminator.step_data.slot])
		violations += 1
	return violations

## Check 4. A phase with no connection steps asks the player for nothing. On
## a terminator phase that means a latch with no wiring behind it; on the
## final phase it means the level is already complete on arrival.
static func _check_no_empty_phases(path: SolutionPath, context: String) -> int:
	var violations: int = 0
	for phase_index in range(path.get_phase_count()):
		if not path.get_phase_connection_steps(phase_index).is_empty():
			continue
		push_error("%s phase %d: no connection steps" % [context, phase_index])
		violations += 1
	return violations

## Check 5. Every (type, slot) any step references must be within the range
## of nodes the level actually builds, or the binding resolver will drop the
## slot and every step touching it becomes permanently unsatisfiable.
static func _check_referential_integrity(path: SolutionPath, available_slot_counts: Dictionary, context: String) -> int:
	var violations: int = 0
	for step in path.solution_steps:
		match step.get_kind():
			SolutionStep.Type.STORE_VALUE:
				violations += _check_slot(step.step_data.STORE_TYPE, step.step_data.slot, available_slot_counts, context)
			SolutionStep.Type.CONNECTION:
				violations += _check_slot(step.step_data.from_type, step.step_data.from_slot, available_slot_counts, context)
				violations += _check_slot(step.step_data.to_type, step.step_data.to_slot, available_slot_counts, context)
	return violations

static func _check_slot(type: NodeTypeRegistry.NodeType, slot: int, available_slot_counts: Dictionary, context: String) -> int:
	var available: int = available_slot_counts.get(type, 0)
	if slot >= 0 and slot < available:
		return 0
	push_error("%s: references slot %d of NodeType %d but the level builds only %d of them" \
			% [context, slot, type, available])
	return 1

## True if any phase from `first_phase` onward draws from the store in
## `slot`. This is the same "read" the liveness analysis uses, so a latch
## that passes here is one that reaches some later phase's required state.
static func _slot_read_after(path: SolutionPath, slot: int, first_phase: int) -> bool:
	for phase_index in range(first_phase, path.get_phase_count()):
		for step in path.get_phase_connection_steps(phase_index):
			if step.step_data.from_type == NodeTypeRegistry.NodeType.STORE \
					and step.step_data.from_slot == slot:
				return true
	return false

## How many nodes of each NodeType the level builds. Inputs and outputs are
## implicitly typed by which array they sit in; operations carry their own
## type.
static func _available_slot_counts(level_data: LevelData) -> Dictionary:
	var counts: Dictionary = {}
	counts[NodeTypeRegistry.NodeType.INPUT] = level_data.inputs.size()
	counts[NodeTypeRegistry.NodeType.OUTPUT] = level_data.outputs.size()
	for operation in level_data.operations:
		counts[operation.type] = counts.get(operation.type, 0) + 1
	return counts

static func _label(context: String) -> String:
	return context if not context.is_empty() else "SolutionPathValidator"
