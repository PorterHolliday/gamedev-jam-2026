extends Node2D

@export var tutorial_button: Button

func _ready() -> void:
	if not tutorial_button.is_node_ready():
		await tutorial_button.ready
	
	await get_tree().create_timer(1.0).timeout
	var tween: Tween = get_tree().create_tween()
	for i in range(5):
		tween.tween_property(tutorial_button, 'modulate', HintVisuals.COLOR, HintVisuals.PULSE_DURATION)
		tween.tween_property(tutorial_button, 'modulate', Color.WHITE, HintVisuals.PULSE_DURATION)
	await tween.finished
