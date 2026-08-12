class_name LevelData
extends Resource

@export var level_scene: PackedScene = preload("res://Levels/level.tscn")

@export var inputs: Array[GraphNodeData] = []
@export var operations: Array[GraphNodeData] = []
@export var outputs: Array[GraphNodeData] = []

@export var level_solution_data: LevelSolutionData
