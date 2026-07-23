class_name GameRoot
extends Node

static var node: GameRoot

@export var title_screen_scene: PackedScene
@export var level_select_screen_scene: PackedScene
@export var settings_screen_scene: PackedScene
@export var credits_screen_scene: PackedScene
@export var menu_music: AudioStream
@export var level_music: AudioStream

@onready var game_screen_root: Node = %GameScreenRoot
@onready var ui_root: UIRoot = %UIRoot
@onready var transition_root: TransitionRoot = %TransitionRoot
@onready var title_screen: Node = title_screen_scene.instantiate()
@onready var level_select_screen: Node = level_select_screen_scene.instantiate()
@onready var settings_screen: Node = settings_screen_scene.instantiate()
@onready var credits_screen: Node = credits_screen_scene.instantiate()

var current_screen: Node:
	set(new_val):
		if current_screen:
			current_screen.hide()
			current_screen.process_mode = Node.PROCESS_MODE_DISABLED
		current_screen = new_val
		current_screen.show()
		current_screen.process_mode = Node.PROCESS_MODE_INHERIT
var previous_screen: Node

func _ready() -> void:
	node = self
	await _add_screens()
	AudioManager.play_music(menu_music)
	current_screen = title_screen

static func enter_level(level: Level) -> void:
	AudioManager.crossfade_music(node.level_music)
	await node.transition(level)
	
static func restart_level() -> void:
	var spare: Level = LevelManager.get_spare_level_instance()
	await node.transition(spare)
	LevelManager.replace_current_level(spare)
	
static func level_complete() -> void:
	node.ui_root.on_level_complete()
	
static func enter_next_level() -> void:
	LevelManager.levels[LevelManager.current_level_index] = LevelManager.get_spare_level_instance()
	await enter_level(LevelManager.get_next_level())
	node.previous_screen.queue_free()
	
static func enter_level_select_screen() -> void:
	AudioManager.crossfade_music(node.menu_music)
	node.level_select_screen.update_level_buttons()
	await node.transition(node.level_select_screen)
	LevelManager.replace_current_level(LevelManager.get_spare_level_instance())
	
static func enter_title_screen() -> void:
	AudioManager.crossfade_music(node.menu_music)
	await node.transition(node.title_screen)
	
static func enter_settings_screen() -> void:
	await node.transition(node.settings_screen)
	
static func exit_settings_screen() -> void:
	await node.transition(node.previous_screen)
		
static func enter_credits_screen() -> void:
	AudioManager.crossfade_music(node.menu_music)
	node.credits_screen.reset_animation()
	await node.transition(node.credits_screen)
	node.credits_screen.logo_animation()
	
func transition(new_screen: Node) -> void:
	current_screen.process_mode = Node.PROCESS_MODE_DISABLED
	await transition_root.transition_in()
	current_screen.hide()
	
	new_screen.show()
	await transition_root.transition_out()
	new_screen.process_mode = Node.PROCESS_MODE_INHERIT
	
	previous_screen = current_screen
	current_screen = new_screen
	
func _add_screens() -> void:
	game_screen_root.add_child(title_screen)
	game_screen_root.add_child(level_select_screen)
	game_screen_root.add_child(settings_screen)
	game_screen_root.add_child(credits_screen)
	
	if not LevelManager.is_node_ready():
		await LevelManager.ready
	for level in LevelManager.levels:
		game_screen_root.add_child(level)
	
	for child in game_screen_root.get_children():
		child.hide()
		child.process_mode = Node.PROCESS_MODE_DISABLED
