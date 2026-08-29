class_name Level
extends Node2D

@export var level_data: LevelData

@onready var level_builder: LevelBuilder = %LevelBuilder
@onready var graph_canvas: GraphCanvas = %GraphCanvas
@onready var ui_layer: CanvasLayer = %UILayer
@onready var back_button: Button = %BackButton
@onready var level_number_label: Label = %LevelNumberLabel
@onready var restart_button: Button = %RestartButton
@onready var hint_button: HintButton = %HintButton
@onready var help_button: Button = %HelpButton
@onready var settings_button: Button = %SettingsButton

var _hint_glow_timer: Timer
var _level_solved: bool = false

func _ready() -> void:
	global_position = Vector2.ZERO
		
	graph_canvas.level_complete.connect(_on_level_complete)
	
	back_button.pressed.connect(_on_back_button_pressed)
	restart_button.pressed.connect(_on_restart_button_pressed)
	hint_button.pressed.connect(_on_hint_button_pressed)
	help_button.pressed.connect(_on_help_button_pressed)
	settings_button.pressed.connect(_on_settings_button_pressed)
	
	level_number_label.text = "Level " + \
		str(LevelManager.level_data_list.find(level_data) + 1) + \
		" of " + str(LevelManager.level_data_list.size())
	
	level_builder.build(level_data)
	graph_canvas.start()
	_start_hint_glow_timer()

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
	GameRoot.enter_level_select_screen()

func _on_restart_button_pressed() -> void:
	GameRoot.restart_level()
	
## Idle-in-level nudge: if the player hasn't solved (or left) the level
## within HintVisuals.HINT_GLOW_IDLE_DELAY, glow the hint button once to
## surface that it exists -- no text, no popup, just a visual cue they're
## free to ignore. Fires at most once ever, across the whole game; every
## level after that just skips arming the timer.
func _start_hint_glow_timer() -> void:
	if SaveManager.has_seen_hint_glow():
		return
	if level_data.level_solution_data == null:
		return

	_hint_glow_timer = Timer.new()
	_hint_glow_timer.wait_time = HintVisuals.HINT_GLOW_IDLE_DELAY
	_hint_glow_timer.one_shot = true
	add_child(_hint_glow_timer)
	_hint_glow_timer.timeout.connect(_on_hint_glow_timer_timeout)
	_hint_glow_timer.start()

func _on_hint_glow_timer_timeout() -> void:
	if _level_solved or SaveManager.has_seen_hint_glow():
		return
	hint_button.glow_pulse(HintVisuals.HINT_GLOW_PULSE_COUNT)
	SaveManager.mark_hint_glow_seen()

func _on_hint_button_pressed() -> void:
	# They found the hint button themselves -- nothing left to nudge them
	# toward, whether or not the idle glow ever got the chance to fire.
	SaveManager.mark_hint_glow_seen()

	var solution_data: LevelSolutionData = level_data.level_solution_data
	if solution_data == null: return

	var steps: Array[SolutionStep] = solution_data.get_next_hint_group(graph_canvas)
	if steps.is_empty():
		graph_canvas.clear_hint_connection()
		return

	var target: Dictionary = solution_data.get_hint_group_target(steps, graph_canvas)
	graph_canvas.set_hint_connections(target["port_pairs"])

	if _should_show_hint_value(steps, target):
		var store_node: MyGraphNode = target["store_node"]
		if store_node is StoreNode:
			store_node.show_hint_value(target["store_value"])

## Whether this hint should pulse the cursor phase's goal value on its
## store. The phase goal is absent entirely on the final phase, which has no
## terminator, so there is nothing to show there either way.
##
## The single read of HintVisuals.SHOW_PHASE_GOAL_VALUE lives here on
## purpose: LevelSolutionData always reports the goal store, and the
## presentation layer decides whether to use it, so the hint system's data
## contract is the same whichever way the flag goes. With the flag off, the
## ghost appears only on the wire that actually causes the latch -- that's
## established behaviour, not part of the experiment.
func _should_show_hint_value(steps: Array[SolutionStep], target: Dictionary) -> bool:
	if not target.has("store_node"):
		return false
	if HintVisuals.SHOW_PHASE_GOAL_VALUE:
		return true
	return steps.size() == 1 \
			and steps[0].step_data.to_type == NodeTypeRegistry.NodeType.STORE

func _on_help_button_pressed() -> void:
	GameRoot.enter_how_to_play_screen()

func _on_settings_button_pressed() -> void:
	GameRoot.enter_settings_screen()

func _on_level_complete() -> void:
	_level_solved = true
	if _hint_glow_timer:
		_hint_glow_timer.stop()

	await graph_canvas.play_level_complete_animation()
	await get_tree().create_timer(0.1).timeout
	
	LevelManager.complete_current_level()
	
	await get_tree().create_timer(0.1).timeout
	process_mode = Node.PROCESS_MODE_DISABLED
