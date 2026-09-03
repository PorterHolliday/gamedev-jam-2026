extends Node

const APP_ID : String = "EQ1AEtI2Y"
const SDK_KEY : String = "184TBmNvPIIvNcNjTpShxfMVMGQwynnMkasEZuDkR0oSCvVt+UqQyyVtSodn2Qb8"

func _ready() -> void:
	if OS.has_feature("web"):
		initialize_bytebrew()

func initialize_bytebrew() -> void:
	var window = JavaScriptBridge.get_interface("window")
	if window:
		if typeof(window.initByteBrew) != TYPE_NIL:
			var app_version : String = ProjectSettings.get_setting("application/config/version", "1.0.0")
			window.initByteBrew(APP_ID, SDK_KEY, app_version)
		else:
			push_error("ByteBrew: initByteBrew function is missing from the global window object.")
	else:
		push_error("ByteBrew: Could not access browser window interface.")

func track_event(event_name: String, parameters: Dictionary = {}) -> void:
	parameters = _inject_web_host(parameters)
	if OS.has_feature("web"):
		var window = JavaScriptBridge.get_interface("window")
		if window and typeof(window.trackCustomEvent) != TYPE_NIL:
			# Convert Godot Dictionary to a JSON string string for robust transfer to JS
			var json_string = JSON.stringify(parameters)
			window.trackCustomEvent(event_name, json_string)
	else:
		print("ByteBrew Mock Track: ", event_name, " Params: ", parameters)

func _inject_web_host(parameters: Dictionary = {}) -> Dictionary:
	parameters["host"] = ""
	if OS.has_feature("itch"):
		parameters["host"] = "itch"
	elif OS.has_feature("crazygames"):
		parameters["host"] = "crazygames"
	elif OS.has_feature("wavedash"):
		parameters["host"] = "wavedash"
	return parameters
