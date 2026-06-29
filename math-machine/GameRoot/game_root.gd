class_name GameRoot
extends Node

static var node: GameRoot

@export var title_screen_scene: PackedScene
@export var level_select_screen_scene: PackedScene
@export var end_screen_scene: PackedScene

@onready var game_screen_root: Node = %GameScreenRoot
@onready var ui_root: Control = %UIRoot
@onready var settings_menu_root: Control = %SettingsMenuRoot
@onready var transition_root: TransitionRoot = %TransitionRoot

var current_screen: Node
var current_screen_scene: PackedScene

func _ready() -> void:
	node = self
	game_screen_root.add_child(title_screen_scene.instantiate())

static func enter_level(level_scene: PackedScene) -> void:
	node.current_screen_scene = level_scene
	node.transition_page_forward(level_scene.instantiate())
	
static func restart_level() -> void:
	node.transition_page_forward(node.current_screen_scene.instantiate())
	
static func level_complete() -> void:
	pass
	
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
	
func transition_page_forward(new_screen: Node) -> void:
	var old_screen: Node = node.game_screen_root.get_child(0)
	node.game_screen_root.remove_child(old_screen)
	node.game_screen_root.add_child(new_screen)
	new_screen.process_mode = Node.PROCESS_MODE_DISABLED
	
	transition_root.play_transition_forward(old_screen)
	await transition_root.transition_finished
	
	old_screen.queue_free()
	new_screen.process_mode = Node.PROCESS_MODE_INHERIT
	node.current_screen = new_screen
	
func transition_page_back(new_screen: Node) -> void:
	var old_screen: Node = node.game_screen_root.get_child(0)
	old_screen.process_mode = Node.PROCESS_MODE_DISABLED
	
	transition_root.play_transition_back(new_screen)
	await transition_root.transition_finished
	
	node.game_screen_root.remove_child(old_screen)
	node.game_screen_root.add_child(new_screen)
	old_screen.queue_free()
	node.current_screen = new_screen
