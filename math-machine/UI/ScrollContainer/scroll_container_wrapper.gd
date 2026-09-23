extends Control

const ARROW_SCROLL_SPEED: float = 400.0

@export var scroll_container: ScrollContainer
@export var up_arrow: TextureRect
@export var down_arrow: TextureRect

var _up_arrow_pressed: bool = false
var _down_arrow_pressed: bool = false

func _ready() -> void:
	up_arrow.gui_input.connect(_on_up_arrow_gui_input)
	down_arrow.gui_input.connect(_on_down_arrow_gui_input)

func _process(delta: float) -> void:
	up_arrow.hide()
	down_arrow.hide()
	if scroll_container.scroll_vertical > 0:
		up_arrow.show()
	if scroll_container.scroll_vertical < scroll_container.get_child(0).size.y - scroll_container.size.y:
		down_arrow.show()
		
	if _up_arrow_pressed:
		scroll_container.scroll_vertical -= ceil(ARROW_SCROLL_SPEED * delta)
	if _down_arrow_pressed:
		scroll_container.scroll_vertical += ceil(ARROW_SCROLL_SPEED * delta)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_up_arrow_pressed = false
		_down_arrow_pressed = false

func _on_up_arrow_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_up_arrow_pressed = event.pressed
	
func _on_down_arrow_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_down_arrow_pressed = event.pressed
