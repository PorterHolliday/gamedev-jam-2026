class_name GameRoot
extends Node

## Root coordinator for screen navigation.
##
## Menu screens (title, level select, settings, credits) are instantiated once
## and kept alive for the whole session. Levels are instantiated on demand
## inside [method _transition], while the screen is fully faded to black, and
## freed as soon as the player leaves them. Only one [Level] exists at a time.

static var node: GameRoot

@export var title_screen_scene: PackedScene
@export var level_select_screen_scene: PackedScene
@export var settings_screen_scene: PackedScene
@export var how_to_play_screen_scene: PackedScene
@export var credits_screen_scene: PackedScene

@onready var game_screen_root: Node = %GameScreenRoot
@onready var ui_root: UIRoot = %UIRoot
@onready var transition_root: TransitionRoot = %TransitionRoot
@onready var title_screen: Node = title_screen_scene.instantiate()
@onready var level_select_screen: Node = level_select_screen_scene.instantiate()
@onready var settings_screen: Node = settings_screen_scene.instantiate()
@onready var how_to_play_screen: HowToPlayScreen = how_to_play_screen_scene.instantiate()
@onready var credits_screen: Node = credits_screen_scene.instantiate()

## Visibility only. Process state is owned by [method _transition] so that a
## screen stays inert until the fade-out has finished.
var current_screen: Node:
	set(new_val):
		if current_screen:
			current_screen.hide()
		current_screen = new_val
		current_screen.show()

## The screen to return to when leaving the settings screen. Cleared whenever
## the screen it pointed at has been freed.
var previous_screen: Node

## The live level instance, or null when no level is loaded.
var current_level: Level

func _ready() -> void:
	node = self
	_add_screens()
	AudioManager.play_menu_music()
	current_screen = title_screen
	title_screen.process_mode = Node.PROCESS_MODE_INHERIT

#region Navigation

static func enter_level(index: int) -> void:
	AudioManager.crossfade_to_level_music()
	await node.transition_to_level(index)

static func restart_level() -> void:
	await node.transition_to_level(LevelManager.current_level_index)

static func enter_next_level() -> void:
	var next_index: int = LevelManager.current_level_index + 1
	if not LevelManager.has_level(next_index):
		await enter_level_select_screen()
		return
	await enter_level(next_index)

static func level_complete() -> void:
	node.ui_root.on_level_complete()

static func enter_level_select_screen() -> void:
	AudioManager.crossfade_to_menu_music()
	node.level_select_screen.update_level_buttons()
	await node.transition(node.level_select_screen)

static func enter_title_screen() -> void:
	AudioManager.crossfade_to_menu_music()
	await node.transition(node.title_screen)

static func enter_settings_screen() -> void:
	await node.transition(node.settings_screen)

static func exit_settings_screen() -> void:
	await node.transition(node.previous_screen)
	
static func enter_how_to_play_screen() -> void:
	node.how_to_play_screen.reset()
	await node.transition(node.how_to_play_screen)
	
static func exit_how_to_play_screen() -> void:
	await node.transition(node.previous_screen)

static func enter_credits_screen() -> void:
	AudioManager.crossfade_to_menu_music()
	node.credits_screen.reset_animation()
	await node.transition(node.credits_screen)
	node.credits_screen.logo_animation()

#endregion

#region Transitions

## Fades to [param new_screen]. Use for persistent menu screens.
func transition(new_screen: Node) -> void:
	await _transition(func() -> Node: return new_screen)

## Fades to the level at [param index], instantiating it while the screen is
## black so the load cost is hidden by the transition.
func transition_to_level(index: int) -> void:
	await _transition(func() -> Node: return await _build_level(index))

## Shared transition core. [param build_screen] is invoked at the moment the
## screen is fully black and must return the destination [Node], or null to
## abort and fade back to the current screen.
func _transition(build_screen: Callable) -> void:
	current_screen.process_mode = Node.PROCESS_MODE_DISABLED
	await transition_root.transition_in()

	var outgoing_level: Level = current_level
	var new_screen: Node = await build_screen.call()
	if new_screen == null:
		current_screen.process_mode = Node.PROCESS_MODE_INHERIT
		await transition_root.transition_out()
		return

	# Levels are disposable, menu screens are not. Settings is exempt because
	# exit_settings_screen() must be able to return to the level behind it.
	var freed_level: bool = false
	if outgoing_level and outgoing_level != new_screen and new_screen != settings_screen and new_screen != how_to_play_screen:
		outgoing_level.queue_free()
		freed_level = true
		current_level = null

	if new_screen is Level:
		current_level = new_screen

	# is_instance_valid() still reports true for a queue_free()d node this
	# frame, so track the free explicitly rather than testing validity.
	previous_screen = null if (freed_level and current_screen == outgoing_level) else current_screen
	current_screen = new_screen

	await transition_root.transition_out()
	new_screen.process_mode = Node.PROCESS_MODE_INHERIT

## Instantiates and parents a level while the screen is black.
## Returns null if [param index] is out of bounds.
func _build_level(index: int) -> Level:
	var level_data: LevelData = LevelManager.get_level_data(index)
	var level: Level = level_data.level_scene.instantiate()

	level.hide()
	level.process_mode = Node.PROCESS_MODE_DISABLED
	level.level_data = level_data
	game_screen_root.add_child(level)
	await get_tree().process_frame  # let _ready and node setup settle while black
	return level

#endregion

func _add_screens() -> void:
	game_screen_root.add_child(title_screen)
	game_screen_root.add_child(level_select_screen)
	game_screen_root.add_child(settings_screen)
	game_screen_root.add_child(how_to_play_screen)
	game_screen_root.add_child(credits_screen)

	for child in game_screen_root.get_children():
		child.hide()
		child.process_mode = Node.PROCESS_MODE_DISABLED
