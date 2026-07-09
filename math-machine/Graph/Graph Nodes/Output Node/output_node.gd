@tool
class_name OutputNode2
extends MyGraphNode

signal received_valid_output

@onready var _sprite: Sprite2D = %Sprite2D
@onready var _value_label: Label = %ValueLabel
@export var value: int = 1:
	set(new_val):
		value = new_val
		if Engine.is_editor_hint():
			_update_value_label()
@export var unsatisfied_color: Color = Color.WHITE:
	set(new_val):
		unsatisfied_color = new_val
		if not is_satisfied:
			_sprite.modulate = unsatisfied_color
@export var unsatisfied_text_color: Color = Color.BLACK:
	set(new_val):
		unsatisfied_text_color = new_val
		if not is_satisfied:
			_value_label.modulate = unsatisfied_text_color
@export var satisfied_color: Color
@export var satisfied_text_color: Color = Color.WHITE

@export var is_satisfied: bool = false:
	set(new_val):
		if not is_satisfied and new_val:
			_play_fill_animation()
		elif is_satisfied and not new_val:
			_play_fill_animation(true)
		is_satisfied = new_val
			
@export var transition_duration: float = 0.5

func _ready() -> void:
	_update_value_label()
	_sprite.material = _sprite.material.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	_value_label.material = _value_label.material.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	_sprite.material.set_shader_parameter('fill_color', satisfied_color)
	_value_label.material.set_shader_parameter('fill_color', satisfied_text_color)
	if Engine.is_editor_hint(): return
	super()
	
func update_input(port: GraphNodePort, new_value: int) -> void:
	super(port, new_value)
	_check_if_satisfied()
	
func remove_input(port: GraphNodePort) -> void:
	super(port)
	is_satisfied = false
	
func _check_if_satisfied() -> void:
	if inputs[0].value == value:
		is_satisfied = true
		received_valid_output.emit()
	else:
		is_satisfied = false

func _update_value_label() -> void:
	if not _value_label: return
	_value_label.text = str(value)

func _play_fill_animation(reverse: bool = false) -> void:
	var sprite_material: ShaderMaterial = _sprite.material
	#sprite_material.set_shader_parameter('invert', reverse)
	var text_material: ShaderMaterial = _value_label.material
	#text_material.set_shader_parameter('invert', reverse)
	var tween: Tween = get_tree().create_tween()
	tween.tween_method(func(value: float):
		sprite_material.set_shader_parameter('progress', value), 
		1.0 - float(!reverse), 1.0 - float(reverse), transition_duration
	)
	tween.parallel().tween_method(func(value: float):
		text_material.set_shader_parameter('progress', value), 
		1.0 - float(!reverse), 1.0 - float(reverse), transition_duration
	)
	
	await tween.finished
