class_name ConnectionStepData
extends SolutionStepData

## Sentinel for from_value/to_value meaning "don't care about this node's
## value." Deliberately NOT MyGraphNode.NULL_VALUE -- that's the max int64,
## and Godot's Inspector SpinBox (float64-backed) silently corrupts values
## that large the moment the field is touched in the editor.
const ANY_VALUE: int = -2147483648

@export var from_type: NodeTypeRegistry.NodeType
@export var from_slot: int = 0
@export var from_port: int = 0
## Required value on the from-node, for types with a fixed, level-authored
## value (Input, Output, Add Value). Leave at ANY_VALUE ("don't care") for
## types with no fixed value (Store, Sum, Subtract, ...).
@export var from_value: int = ANY_VALUE
@export var to_type: NodeTypeRegistry.NodeType
@export var to_slot: int = 0
@export var to_port: int = 0
## See from_value.
@export var to_value: int = ANY_VALUE
