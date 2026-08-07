class_name HapticData
extends Resource

@export var pattern: Array[int] = []
@export var amplitude: Array[float] = []

func _init(_pattern: Array[int] = [], _amplitude: Array[float] = [1.0]) -> void:
	pattern = _pattern
	amplitude = _amplitude
