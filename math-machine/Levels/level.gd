class_name Level
extends Node2D

@onready var graph_canvas: GraphCanvas = %GraphCanvas
@onready var ui_layer: CanvasLayer = %UILayer
@onready var back_button: Button = %BackButton
@onready var restart_button: Button = %RestartButton
@onready var hint_button: Button = %HintButton
@onready var settings_button: Button = %SettingsButton
@onready var animation_player: AnimationPlayer = %AnimationPlayer

func _ready() -> void:
	global_position = Vector2.ZERO
		
	graph_canvas.level_complete.connect(_on_level_complete)
	
	back_button.pressed.connect(_on_back_button_pressed)
	restart_button.pressed.connect(_on_restart_button_pressed)
	hint_button.pressed.connect(_on_hint_button_pressed)
	settings_button.pressed.connect(_on_settings_button_pressed)
	
	back_button.pressed.connect(_on_button_pressed)
	restart_button.pressed.connect(_on_button_pressed)
	hint_button.pressed.connect(_on_button_pressed)
	settings_button.pressed.connect(_on_button_pressed)
	
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		if not ui_layer: return
		ui_layer.visible = visible
		
func disable() -> void:
	hide()
	graph_canvas.process_mode = Node.PROCESS_MODE_DISABLED
	
func enable() -> void:
	show()
	graph_canvas.process_mode = Node.PROCESS_MODE_INHERIT

func _on_back_button_pressed() -> void:
	await GameRoot.enter_level_select_screen()
	LevelManager.replace_current_level(LevelManager.get_spare_level_instance(false))
	
func _on_restart_button_pressed() -> void:
	GameRoot.restart_level()
	
func _on_hint_button_pressed() -> void:
	animation_player.play('show_hint')
	
func _on_settings_button_pressed() -> void:
	GameRoot.enter_settings_screen()
	
func _on_button_pressed() -> void:
	AudioManager.play_button_click_sfx()

func _on_level_complete() -> void:	
	await graph_canvas.play_level_complete_animation()
	await get_tree().create_timer(0.1).timeout
	
	LevelManager.complete_current_level()
	
	await get_tree().create_timer(0.1).timeout
	process_mode = Node.PROCESS_MODE_DISABLED
