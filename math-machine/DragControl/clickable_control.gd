@tool
class_name ClickableControl
extends Control

## Emitted when the input area is pressed.
signal mouse_clicked(button_index: MouseButton)
## Emitted when the input area is released.
signal mouse_released(button_index: MouseButton)

const TOUCH_TO_RIGHT_CLICK_TIME: float = 0.8
const TOUCH_MOVE_TOLERANCE: float = 8.0

## Shape used for hit-testing, positioned relative to the Control's origin
## (top-left corner), not its size. If null, falls back to the default
## rectangular Control bounds.
@export var shape: Shape2D = null:
	set(value):
		shape = value
		queue_redraw()

## Draw the shape outline in the editor for visual debugging.
@export var show_shape_in_editor: bool = true:
	set(value):
		show_shape_in_editor = value
		queue_redraw()

@export var shape_color: Color = Color(0.4, 0.8, 1.0, 0.5)

var is_clicked: bool = false
var _touch_initial_position: Vector2 = Vector2.ZERO

@onready var touch_timer: Timer = Timer.new()

func _ready() -> void:
	add_child(touch_timer)
	touch_timer.timeout.connect(_on_touch_timer_timeout)

func _has_point(point: Vector2) -> bool:
	if shape == null:
		return _default_has_point(point)

	if shape is CircleShape2D:
		return point.length() <= shape.radius

	if shape is RectangleShape2D:
		var extents: Vector2 = shape.size / 2.0
		return abs(point.x) <= extents.x and abs(point.y) <= extents.y

	if shape is CapsuleShape2D:
		var half_height: float = shape.height / 2.0 - shape.radius
		var clamped_y: float = clampf(point.y, -half_height, half_height)
		var closest: Vector2 = Vector2(0.0, clamped_y)
		return point.distance_to(closest) <= shape.radius

	if shape is ConvexPolygonShape2D:
		return Geometry2D.is_point_in_polygon(point, shape.points)

	# Unsupported Shape2D type; fall back to default rectangular bounds.
	return _default_has_point(point)

func _default_has_point(point: Vector2) -> bool:
	return Rect2(Vector2.ZERO, size).has_point(point)

func _draw() -> void:
	if not Engine.is_editor_hint(): return
	if not show_shape_in_editor: return
	if shape == null: return

	if shape is CircleShape2D:
		draw_circle(Vector2.ZERO, shape.radius, shape_color)

	elif shape is RectangleShape2D:
		var extents: Vector2 = shape.size / 2.0
		draw_rect(Rect2(-extents, shape.size), shape_color)

	elif shape is CapsuleShape2D:
		var half_height: float = shape.height / 2.0 - shape.radius
		var points: PackedVector2Array = PackedVector2Array()
		var segments: int = 16

		for i in range(segments + 1):
			var angle: float = PI - i * PI / segments
			points.append(Vector2(shape.radius, 0).rotated(angle) + Vector2(0, -half_height))
		for i in range(segments + 1):
			var angle: float = -i * PI / segments
			points.append(Vector2(shape.radius, 0).rotated(angle) + Vector2(0, half_height))
		points.append(points[0])

		draw_colored_polygon(points, shape_color)

	elif shape is ConvexPolygonShape2D:
		if shape.points.size() >= 3:
			draw_colored_polygon(shape.points, shape_color)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_initial_position = event.position
			touch_timer.one_shot = true
			touch_timer.start(TOUCH_TO_RIGHT_CLICK_TIME)
		else:
			touch_timer.stop()
	if event is InputEventScreenDrag:
		if event.position.distance_to(_touch_initial_position) > TOUCH_MOVE_TOLERANCE:
			touch_timer.stop()
	if event is InputEventMouseButton and event.pressed:
		is_clicked = true
		mouse_clicked.emit(event.button_index)
		#accept_event()

# Once clicked, track release globally so dragging outside the shape
# still delivers the release event to this control.
func _input(event: InputEvent) -> void:
	if not is_clicked: return
	if event is InputEventMouseButton and not event.pressed:
		is_clicked = false
		mouse_released.emit(event.button_index)
		#get_viewport().set_input_as_handled()
		
func _on_touch_timer_timeout() -> void:
	HapticManager.trigger_right_click_haptic()
	mouse_released.emit(MOUSE_BUTTON_LEFT)
	mouse_clicked.emit(MOUSE_BUTTON_RIGHT)
