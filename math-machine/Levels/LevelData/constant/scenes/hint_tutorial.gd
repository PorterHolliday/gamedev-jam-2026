extends Node2D

@export var hint_button: HintButton

func _ready() -> void:
	if not hint_button.is_node_ready():
		await hint_button.ready
	
	await get_tree().create_timer(1.0).timeout
	hint_button.glow_pulse(5)
