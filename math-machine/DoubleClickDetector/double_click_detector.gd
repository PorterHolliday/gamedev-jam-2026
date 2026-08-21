class_name DoubleClickDetector
extends Node

## Emitted when a double click/tap is detected at the given position.
signal double_clicked(position: Vector2, button_index: MouseButton)

@export var double_click_time: float = 0.3
@export var double_click_distance: float = 16.0
@export var button_mask: Array[MouseButton] = [MOUSE_BUTTON_LEFT]

var _last_click_time: float = -INF
var _last_click_position: Vector2 = Vector2.ZERO

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton: return
	if not event.pressed: return
	if not button_mask.has(event.button_index): return

	var now: float = Time.get_ticks_msec() / 1000.0
	var is_double: bool = event.double_click \
		or (now - _last_click_time <= double_click_time \
			and event.position.distance_to(_last_click_position) <= double_click_distance)

	_last_click_time = now
	_last_click_position = event.position

	if not is_double: return

	double_clicked.emit(event.position, event.button_index)
	get_viewport().set_input_as_handled()

	# Prevent a third click from chaining into another double-click detection.
	_last_click_time = -INF
