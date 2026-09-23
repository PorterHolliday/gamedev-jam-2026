extends Node

signal adbreak_completed

const ATTEMPT_ADBREAK_TIME: float = 1.0

var _callback_adbreak_start: JavaScriptObject
var _callback_adbreak_complete: JavaScriptObject

@onready var attempt_adbreak_timer: Timer = Timer.new()

func _ready() -> void:
	if not (OS.has_feature('web') and OS.has_feature('coolmathgames')): return
	
	_callback_adbreak_start = JavaScriptBridge.create_callback(_on_adbreak_start)
	_callback_adbreak_complete = JavaScriptBridge.create_callback(_on_adbreak_complete)
	JavaScriptBridge.get_interface("document").addEventListener("adBreakStart", _callback_adbreak_start)
	JavaScriptBridge.get_interface("document").addEventListener("adBreakComplete", _callback_adbreak_complete)
	
	add_child(attempt_adbreak_timer)
	attempt_adbreak_timer.one_shot = true
	attempt_adbreak_timer.timeout.connect(_on_attempt_adbreak_timer_timeout)

func on_game_started() -> void:
	if not (OS.has_feature("web") and OS.has_feature("coolmathgames")): return
	JavaScriptBridge.eval("window.parent.postMessage({'cm_game_event': true, 'cm_game_evt': 'start', 'cm_game_lvl': 0}, '*')", true)

func on_level_started(level_index: int) -> void:
	if not (OS.has_feature("web") and OS.has_feature("coolmathgames")): return
	JavaScriptBridge.eval("window.parent.postMessage({'cm_game_event': true, 'cm_game_evt': 'start', 'cm_game_lvl': %d}, '*');" % (level_index+1), true)

func on_level_restarted(level_index: int) -> void:
	if not (OS.has_feature("web") and OS.has_feature("coolmathgames")): return
	JavaScriptBridge.eval("window.parent.postMessage({'cm_game_event': true, 'cm_game_evt': 'replay', 'cm_game_lvl': %d}, '*');" % (level_index+1), true)

func cmg_adbreak() -> void:
	if not (OS.has_feature("web") and OS.has_feature("coolmathgames")): return
	JavaScriptBridge.eval("cmgAdBreak();", true)
	attempt_adbreak_timer.start(ATTEMPT_ADBREAK_TIME)
	await adbreak_completed

func _on_adbreak_start(args: Array) -> void:
	print("AdBreak Started")
	get_tree().paused = true
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)

func _on_adbreak_complete(args: Array) -> void:
	print("AdBreak Completed")
	get_tree().paused = false
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), false)
	attempt_adbreak_timer.stop()
	adbreak_completed.emit()
	
func _on_attempt_adbreak_timer_timeout() -> void:
	adbreak_completed.emit()
