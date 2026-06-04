@tool
class_name DirectionalExpandContainer
extends Container

enum ExpandDirection {
	BEGIN,
	END,
	BOTH
}

## Controls which point stays anchored when the container changes size.
@export var h_expand_direction: ExpandDirection = ExpandDirection.END:
	set(value):
		h_expand_direction = value
		queue_sort()
@export var v_expand_direction: ExpandDirection = ExpandDirection.END:
	set(value):
		v_expand_direction = value
		queue_sort()
@onready var old_size: Vector2 = get_combined_minimum_size()

func _get_minimum_size() -> Vector2:
	## Report the union of all children's minimum sizes so the parent layout
	## knows how small this container can get.
	var min_size := Vector2.ZERO
	for child in get_children():
		var control := child as Control
		if control == null or not control.visible:
			continue
		var child_min := control.get_combined_minimum_size()
		min_size.x = maxf(min_size.x, child_min.x)
		min_size.y = maxf(min_size.y, child_min.y)
	return min_size
 
 
func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		_do_layout()
 
 
## Fits all children to fill the container, then repositions the container so
## the anchor point does not move.
func _do_layout() -> void:
	var new_size: Vector2 = get_combined_minimum_size()
 
	# --- 1. Compute how much the width changes and which edge is the anchor. ---
	var delta_x: float = new_size.x - old_size.x
	var delta_y: float = new_size.y - old_size.y
 
	# --- 2. Shift position to compensate, keeping the anchor edge stationary.
	#         position is local to the parent — safe to write as long as this
	#         node is not managed by a parent Container. ---
	match h_expand_direction:
		ExpandDirection.END:
			# Left edge is anchor — no position adjustment needed.
			pass
		ExpandDirection.BEGIN:
			# Right edge is anchor — move left by the full delta.
			position.x -= delta_x
		ExpandDirection.BOTH:
			# Center is anchor — move left by half the delta (floor bias).
			position.x -= floorf(delta_x * 0.5)
	match v_expand_direction:
		ExpandDirection.END:
			pass
		ExpandDirection.BEGIN:
			position.y -= delta_y
		ExpandDirection.BOTH:
			position.y -= floorf(delta_y * 0.5)
 
	# --- 3. Apply the new size. ---
	size = new_size
	old_size = size
 
	# --- 4. Fit every child to the full container rect. ---
	for child in get_children():
		var control := child as Control
		if control == null or not control.visible:
			continue
		fit_child_in_rect(control, Rect2(Vector2.ZERO, new_size))
