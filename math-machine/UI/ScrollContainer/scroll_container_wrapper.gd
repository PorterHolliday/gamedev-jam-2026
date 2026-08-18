extends Control

@export var scroll_container: ScrollContainer
@export var up_arrow: TextureRect
@export var down_arrow: TextureRect

func _process(delta: float) -> void:
	up_arrow.hide()
	down_arrow.hide()
	if scroll_container.scroll_vertical > 0:
		up_arrow.show()
	if scroll_container.scroll_vertical < scroll_container.size.y + size.y:
		down_arrow.show()
