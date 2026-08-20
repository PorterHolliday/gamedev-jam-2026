class_name HintButton
extends MyButton

func glow_pulse(times: int) -> void:
	modulate = HintVisuals.COLOR
	var tween: Tween = get_tree().create_tween()
	for i in range(times):
		tween.tween_property(self, 'modulate', HintVisuals.COLOR, HintVisuals.PULSE_DURATION)
		tween.tween_property(self, 'modulate', Color.WHITE, HintVisuals.PULSE_DURATION)
	await tween.finished
