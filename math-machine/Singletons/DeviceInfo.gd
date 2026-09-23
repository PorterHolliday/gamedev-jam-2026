extends Node

var is_mobile: bool = false
var has_small_speakers: bool = false

func _init() -> void:
	_check_if_mobile()
	_check_if_small_speakers()

func _check_if_mobile() -> void:
	if OS.has_feature("web_android") or OS.has_feature("web_ios"):
		is_mobile = true
	if OS.has_feature("web_macos") and DisplayServer.is_touchscreen_available():
		is_mobile = true
		
func _check_if_small_speakers() -> void:
	has_small_speakers = is_mobile
