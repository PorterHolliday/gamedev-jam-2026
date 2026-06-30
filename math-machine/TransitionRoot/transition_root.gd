class_name TransitionRoot
extends Control

signal transition_finished

@export var transition_duration: float = 0.5;

@onready var sub_viewport: SubViewport = %SubViewport

func play_transition_forward(old_screen: Node) -> void:
	sub_viewport.add_child(old_screen)
	
	var shader_material: ShaderMaterial = material
	var tween: Tween = get_tree().create_tween()
	tween.tween_method(func(value: float):
		shader_material.set_shader_parameter('progress', value), 
		0.0, 1.0, transition_duration
	)
	await tween.finished
	
	sub_viewport.remove_child(old_screen)
	shader_material.set_shader_parameter('progress', 0.0)
	transition_finished.emit()
	
func play_transition_back(new_screen: Node) -> void:
	sub_viewport.add_child(new_screen)
	
	var shader_material: ShaderMaterial = material
	var tween: Tween = get_tree().create_tween()
	tween.tween_method(func(value: float):
		shader_material.set_shader_parameter('progress', value), 
		1.0, 0.0, transition_duration
	)
	await tween.finished
	
	sub_viewport.remove_child(new_screen)
	shader_material.set_shader_parameter('progress', 0.0)
	transition_finished.emit()
