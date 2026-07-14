class_name GameRoot
extends Node

static var node: GameRoot

@export var title_screen_scene: PackedScene
@export var level_select_screen_scene: PackedScene
@export var end_screen_scene: PackedScene
@export var settings_screen_scene: PackedScene
@export var credits_screen_scene: PackedScene

@onready var game_screen_root: Node = %GameScreenRoot
@onready var ui_root: UIRoot = %UIRoot
@onready var settings_menu_root: Control = %SettingsMenuRoot
@onready var transition_root: TransitionRoot = %TransitionRoot

var current_screen: Node
var current_screen_scene: PackedScene
var previous_screen: Node

func _ready() -> void:
	node = self
	var title_screen: Node = title_screen_scene.instantiate()
	game_screen_root.add_child(title_screen)
	current_screen = title_screen
	current_screen_scene = title_screen_scene

static func enter_level(level_scene: PackedScene) -> void:
	node.current_screen_scene = level_scene
	node.transition_page_forward(level_scene.instantiate())
	
static func restart_level() -> void:
	node.transition_page_forward(LevelManager.get_current_level_scene().instantiate())
	
static func level_complete() -> void:
	node.ui_root.on_level_complete()
	
static func enter_next_level() -> void:
	node.transition_page_forward(LevelManager.get_next_level_scene().instantiate())
	
static func enter_level_select_screen() -> void:
	var level_select_screen: Control = node.level_select_screen_scene.instantiate()
	if node.current_screen is Level:
		node.transition_page_back(level_select_screen)
	else:
		node.transition_page_forward(level_select_screen)
	
static func enter_title_screen() -> void:
	var title_screen: Control = node.title_screen_scene.instantiate()
	node.transition_page_back(title_screen)
	
static func enter_end_screen() -> void:
	var end_screen: Control = node.end_screen_scene.instantiate()
	node.transition_page_forward(end_screen)
	
static func enter_settings_screen() -> void:
	var settings_screen: Control = node.settings_screen_scene.instantiate()
	if node.current_screen is Level:
		node.transition_page_back(settings_screen)
	else:
		node.transition_page_forward(settings_screen)
	
static func exit_settings_screen() -> void:
	if node.previous_screen is Level:
		node.transition_page_forward(node.previous_screen)
	else:
		node.transition_page_back(node.previous_screen)
		
static func enter_credits_screen() -> void:
	var credits_screen: Control = node.credits_screen_scene.instantiate()
	node.transition_page_forward(credits_screen)
	
func transition_page_forward(new_screen: Node) -> void:
	var old_screen: Node = node.game_screen_root.get_child(0)
	node.game_screen_root.remove_child(old_screen)
	node.game_screen_root.add_child(new_screen)
	new_screen.process_mode = Node.PROCESS_MODE_DISABLED
	
	transition_root.play_transition_forward(old_screen)
	await transition_root.transition_finished
	
	if previous_screen and previous_screen != new_screen:
		previous_screen.queue_free()
	previous_screen = old_screen
	new_screen.process_mode = Node.PROCESS_MODE_INHERIT
	node.current_screen = new_screen
	
func transition_page_back(new_screen: Node) -> void:
	var old_screen: Node = node.game_screen_root.get_child(0)
	old_screen.process_mode = Node.PROCESS_MODE_DISABLED
	
	transition_root.play_transition_back(new_screen)
	await transition_root.transition_finished
	
	node.game_screen_root.remove_child(old_screen)
	node.game_screen_root.add_child(new_screen)
	if previous_screen and previous_screen != new_screen:
		previous_screen.queue_free()
	previous_screen = old_screen
	node.current_screen = new_screen
