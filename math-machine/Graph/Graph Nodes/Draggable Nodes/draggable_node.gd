class_name DraggableNode
extends MyGraphNode

var audio_stream: AudioStream = preload("res://Audio/SFX/Tone2A.wav")
@onready var audio_player: AudioStreamPlayer = AudioStreamPlayer.new()

var _dragging := false
var _drag_offset := Vector2.ZERO
var _snapping_enabled := false
var _snapping_distance := 0.0
var _position_offset := Vector2.ZERO
var _held := false  # tracks whether node is currently "held"

func _ready() -> void:
	super()

	pivot_offset = size / 2

	audio_player.stream = audio_stream
	add_child(audio_player)

	_position_offset = position_offset
	_snapping_enabled = get_parent().snapping_enabled
	_snapping_distance = get_parent().snapping_distance

	for child in get_children():
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_PASS

func _process(_delta: float) -> void:
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	
	if _held:
		scale = Vector2(1.05, 1.05)
	else:
		scale = Vector2(1, 1)
	
	if not _dragging and position_offset != _position_offset:
		_position_offset = position_offset

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_offset = get_local_mouse_position()
			_on_pick_up()
			get_viewport().set_input_as_handled()
		else:
			_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		_position_offset += event.relative / get_parent().zoom
		if not _snapping_enabled:
			position_offset = _position_offset
		else:
			var snap := _snapping_distance
			position_offset = Vector2(Vector2i((_position_offset + Vector2(snap, snap) / 2.0) / snap)) * snap
		get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	if event.pressed:
		# Title-bar click: mouse is over node but _gui_input didn't fire
		if not _held and get_global_rect().has_point(event.global_position):
			_on_pick_up()
	else:
		# Any release while held
		if _held:
			_dragging = false
			_on_put_down()

func _on_pick_up() -> void:
	if _held:
		return
	_held = true
	
	audio_player.volume_db = randf_range(0, 5)
	audio_player.pitch_scale = randf_range(0.6, 0.8)
	audio_player.play()

func _on_put_down() -> void:
	if not _held:
		return
	_held = false
	
	audio_player.volume_db = randf_range(0, 5)
	audio_player.pitch_scale = randf_range(0.4, 0.6)
	audio_player.play()
