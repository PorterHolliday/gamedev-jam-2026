class_name PathEvaluation
extends RefCounted
## The result of evaluating one SolutionPath against the current board.
##
## Carries the node bindings that scored best, the phase cursor those
## bindings imply, and the score the two were ranked by. Bindings and
## cursor are chosen jointly (see SolutionPath.evaluate) because each
## depends on the other: the cursor is read off the values held by bound
## store nodes, and a binding is only as good as the cursor it reaches.

# Regular variables

## Vector2i(NodeType, slot) -> the live MyGraphNode filling that slot.
var bindings: Dictionary = {}
## Highest phase index whose required_state currently holds. Always valid;
## phase 0 requires nothing, so a cursor always exists.
var phase_index: int = 0
## (cursor, satisfied connections in the cursor phase, -(unsatisfied
## connection steps from the cursor phase to the end)), compared
## lexicographically. The third component is negated so that "more is
## better" holds for every component.
var score: Vector3i = Vector3i(-1, -1, -1)
