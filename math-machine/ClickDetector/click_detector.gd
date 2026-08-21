class_name ClickDetector
extends Node

## Emitted when a click/tap is detected at the given position.
signal clicked(position: Vector2, button_index: MouseButton)

@export var click_time: float = 0.3
@export var click_distance: float = 4.0
@export var button_mask: Array[MouseButton] = [MOUSE_BUTTON_LEFT]

var _last_click_time: float = -INF
var _last_click_position: Vector2 = -Vector2.INF

func _input(event: InputEvent) -> void:
	if not event is InputEventMouseButton: return
	if not button_mask.has(event.button_index): return

	var now: float = Time.get_ticks_msec() / 1000.0

	if event.is_pressed(): 
		_last_click_time = now
		_last_click_position = event.position
		return

	if _last_click_time + click_time >= now \
		and _last_click_position.distance_to(event.position) <= click_distance:
		clicked.emit(event.position, event.button_index)

	_last_click_time = -INF
	_last_click_position = -Vector2.INF

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton: return
	if not button_mask.has(event.button_index): return
	
	var now: float = Time.get_ticks_msec() / 1000.0

	if event.is_pressed(): 
		_last_click_position = event.position
		return

	if _last_click_time + click_time >= now \
		and _last_click_position.distance_to(event.position) <= click_distance:
		clicked.emit(event.position, event.button_index)
		get_viewport().set_input_as_handled()

	_last_click_position = -Vector2.INF
