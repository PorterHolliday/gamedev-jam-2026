extends Node

@onready var port_click_haptic: HapticData = HapticData.new([15])
@onready var port_snap_haptic: HapticData = HapticData.new([15])
@onready var port_connect_haptic: HapticData = HapticData.new([])
@onready var port_disconnect_haptic: HapticData = HapticData.new([])
@onready var pickup_haptic: HapticData = HapticData.new([25])
@onready var drop_haptic: HapticData = HapticData.new([15])
@onready var button_haptic: HapticData = HapticData.new([15])
@onready var right_click_haptic: HapticData = HapticData.new([15])

var haptics_enabled: bool = true

func trigger_port_click_haptic() -> void:
	_trigger_haptic(port_click_haptic)

func trigger_port_snap_haptic() -> void:
	_trigger_haptic(port_snap_haptic)
	
func trigger_port_connect_haptic() -> void:
	_trigger_haptic(port_connect_haptic)
	
func trigger_port_disconnect_haptic() -> void:
	_trigger_haptic(port_disconnect_haptic)
	
func trigger_pickup_haptic() -> void:
	_trigger_haptic(pickup_haptic)
	
func trigger_drop_haptic() -> void:
	_trigger_haptic(drop_haptic)
	
func trigger_button_haptic() -> void:
	_trigger_haptic(button_haptic)
	
func trigger_right_click_haptic() -> void:
	_trigger_haptic(right_click_haptic)

func _trigger_haptic(haptic: HapticData) -> void:
	if not haptics_enabled:
		return
	
	if OS.has_feature("web"):
		_trigger_web_haptic(haptic)
	else:
		_trigger_native_haptic(haptic)

func _trigger_web_haptic(haptic: HapticData) -> void:
	JavaScriptBridge.eval("if (navigator.vibrate) { navigator.vibrate(%s); }" % str(haptic.pattern))
	
func _trigger_native_haptic(haptic: HapticData) -> void:
	var i: int = 0
	var amplitude: float = haptic.amplitude[0]
	while i < haptic.pattern.size():
		var vibration_duration: float = haptic.pattern[i]
		if int(i / 2) < haptic.amplitude.size():
			amplitude = haptic.amplitude[floori(i / 2)]
		Input.vibrate_handheld(vibration_duration, amplitude)
		i += 1
		if i < haptic.pattern.size():
			var wait_duration: float = vibration_duration + haptic.pattern[i] * 0.001
			i += 1
			# Create timer that is haptic time + wait time in milliseconds
			await get_tree().create_timer(wait_duration).timeout
	
# TO-DO: Get haptic plugins for Android and iOS and configure them
func _trigger_android_haptic(haptic: Array[int]) -> void:
	pass
	
func _trigger_ios_haptic(haptic: Array[int]) -> void:
	pass
