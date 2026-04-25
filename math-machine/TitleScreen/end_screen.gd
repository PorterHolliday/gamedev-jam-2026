extends Control

func _ready() -> void:
	for child in get_children():
		if child is GPUParticles2D:
			child.preprocess = randf_range(child.lifetime, child.lifetime * 2)
