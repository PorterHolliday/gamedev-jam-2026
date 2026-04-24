class_name Level
extends Control

signal back_button_pressed
signal restarted
signal completed

@onready var graph_edit: MyGraphEdit = %GraphEdit
@onready var back_button: Button = %BackButton
@onready var restart_button: Button = %RestartButton
@onready var hint_button: Button = %HintButton
@onready var hint: Label = %Hint
@onready var animation_player: AnimationPlayer = %AnimationPlayer
@onready var button_audio: AudioStreamPlayer = %ButtonAudio
@onready var level_complete_audio: AudioStreamPlayer = %LevelCompleteAudio
@onready var music: AudioStreamPlayer = %Music

var level_output_node: LevelOutputNode

func _ready() -> void:
	global_position = Vector2.ZERO
		
	for child in graph_edit.get_children():
		if child is LevelOutputNode:
			level_output_node = child
		
	graph_edit.level_complete.connect(_on_level_complete)
	
	back_button.pressed.connect(_on_back_button_pressed)
	restart_button.pressed.connect(_on_restart_button_pressed)
	hint_button.pressed.connect(_on_hint_button_pressed)
	
	back_button.pressed.connect(_on_button_pressed)
	restart_button.pressed.connect(_on_button_pressed)
	hint_button.pressed.connect(_on_button_pressed)
	
	music.play()
		
func disable() -> void:
	hide()
	graph_edit.process_mode = Node.PROCESS_MODE_DISABLED
	
func enable() -> void:
	show()
	graph_edit.process_mode = Node.PROCESS_MODE_INHERIT

func _on_back_button_pressed() -> void:
	music.stop()
	back_button_pressed.emit()
	
func _on_restart_button_pressed() -> void:
	restarted.emit()
	
func _on_hint_button_pressed() -> void:
	hint.show()
	
func _on_button_pressed() -> void:
	button_audio.volume_db = randf_range(-0.5, 0.5)
	button_audio.pitch_scale = randf_range(0.8, 1.2)
	button_audio.play(0.15)

# Hides level first time it is completed
func _on_level_complete() -> void:
	music.stop()
	hint.hide()
	
	level_complete_audio.stream = load("res://Audio/SFX/LevelCompleteClick.mp3")
	level_complete_audio.play()
	await get_tree().create_timer(1.0).timeout
	
	level_complete_audio.stream = load("res://Audio/SFX/soundreality-notification-tone-443095.mp3")
	level_complete_audio.play()
	
	animation_player.play('level_complete')
	await animation_player.animation_finished
	
	completed.emit()
