extends Node

## Owns every audio stream in the game and all playback policy.
##
## Callers ask for a named track ([method crossfade_to_level_music]) rather than
## passing a stream in, so no other node needs to hold music resources.

const SFX_PLAYER_POOL_COUNT: int = 5
const MOBILE_SFX_VOLUME_DB: float = -6.0
## Effectively silent, used while priming streams at startup.
const WARMUP_DB: float = -80.0

@export_group('Music')
@export var menu_music: AudioStream
@export var level_music: AudioStream

@export_group('SFX')
@export var button_click_sfx: AudioStream
@export var connection_sfx: AudioStream
@export var disconnection_sfx: AudioStream
@export var grab_sfx: AudioStream
@export var drop_sfx: AudioStream
@export var output_satisfied_sfx: AudioStream
@export var level_complete_sfx: AudioStream

@onready var music_player_a: AudioStreamPlayer = AudioStreamPlayer.new()
@onready var music_player_b: AudioStreamPlayer = AudioStreamPlayer.new()

var sfx_player_pool: Array[AudioStreamPlayer] = []
var visibility_callback

func _ready() -> void:
	add_child(music_player_a)
	music_player_a.bus = 'Music'
	add_child(music_player_b)
	music_player_b.bus = 'Music'
	
	for i in range(SFX_PLAYER_POOL_COUNT):
		var sfx_player: AudioStreamPlayer = AudioStreamPlayer.new()
		sfx_player_pool.append(sfx_player)
		add_child(sfx_player)
		sfx_player.bus = 'SFX'
		if OS.has_feature('web_android') or OS.has_feature('web_ios'):
			sfx_player.volume_db = MOBILE_SFX_VOLUME_DB
	# Not awaited: startup must not block on this.
	_warm_up_music()
	_setup_visibility_change_listener()

#region Music

func play_menu_music() -> void:
	_play_music(menu_music)
	
func play_level_music() -> void:
	_play_music(level_music)

func crossfade_to_menu_music(duration: float = 0.75) -> void:
	await _crossfade_music(menu_music, duration)

func crossfade_to_level_music(duration: float = 0.75) -> void:
	await _crossfade_music(level_music, duration)

## Primes every music track so the cost of the first playback is paid during
## startup rather than mid-transition.
##
## An AudioStream is fully loaded before the game starts, but the first call to
## play() is what instantiates a playback and first touches the decoded data.
## For the multi-megabyte music tracks that is long enough to visibly freeze the
## frame it happens on, which is why entering the first level used to stutter
## before the fade had begun. A dedicated silent player is used so the
## crossfade players are left untouched.
func _warm_up_music() -> void:
	var warmup_player: AudioStreamPlayer = AudioStreamPlayer.new()
	warmup_player.bus = 'Music'
	warmup_player.volume_db = WARMUP_DB
	add_child(warmup_player)

	for track in [menu_music, level_music]:
		if track == null: continue
		warmup_player.stream = track
		warmup_player.play()
		# Two frames so the stream is actually mixed, not merely instantiated.
		await get_tree().process_frame
		await get_tree().process_frame
		warmup_player.stop()

	warmup_player.stream = null
	warmup_player.queue_free()

func _play_music(audio: AudioStream) -> void:
	if music_player_a.stream == audio or music_player_b.stream == audio: return
	
	var music_player: AudioStreamPlayer = music_player_a
	if music_player_a.playing:
		music_player = music_player_b
		
	music_player.stream = audio
	music_player.play()

func _crossfade_music(audio: AudioStream, duration: float = 0.75) -> void:
	if music_player_a.stream == audio or music_player_b.stream == audio: return
	
	var active_music_player: AudioStreamPlayer = music_player_a
	var inactive_music_player: AudioStreamPlayer = music_player_b
	if music_player_a.playing:
		active_music_player = music_player_a
		inactive_music_player = music_player_b
	elif music_player_b.playing:
		active_music_player = music_player_b
		inactive_music_player = music_player_a
		
	inactive_music_player.stream = audio
	inactive_music_player.volume_linear = 0.0
	inactive_music_player.play()
	var tween = get_tree().create_tween()
	tween.tween_property(inactive_music_player, 'volume_linear', 1.0, duration)
	tween.parallel().tween_property(active_music_player, 'volume_linear', 0.0, duration)
	
	await tween.finished
	active_music_player.stop()
	active_music_player.stream = null

#endregion

#region SFX

func play_sfx(audio: AudioStream, from_position: float = 0.0) -> AudioStreamPlayer:
	var sfx_player: AudioStreamPlayer = _get_sfx_player()
	sfx_player.stream = audio
	sfx_player.play(from_position)
	return sfx_player
	
func play_button_click_sfx() -> void:
	play_sfx(button_click_sfx)
	
func play_connection_sfx() -> void:
	play_sfx(connection_sfx)
	
func play_disconnection_sfx() -> void:
	play_sfx(disconnection_sfx)
	
func play_grab_sfx() -> void:
	play_sfx(grab_sfx)
	
func play_drop_sfx() -> void:
	var player: AudioStreamPlayer = play_sfx(drop_sfx)
	player.pitch_scale = 0.7
	await player.finished
	player.pitch_scale = 1.0
	
func play_output_satisfied_sfx() -> void:
	play_sfx(output_satisfied_sfx)
	
func play_level_complete_sfx() -> void:
	play_sfx(level_complete_sfx)
	
func _get_sfx_player() -> AudioStreamPlayer:
	for sfx_player in sfx_player_pool:
		if sfx_player.playing: continue
		return sfx_player
	# Pool exhausted: steal the oldest rather than returning null, which every
	# caller would dereference immediately.
	return sfx_player_pool[0]

#endregion

func _setup_visibility_change_listener() -> void:
	if OS.has_feature("web"):
		# Create a callback that points to a function in this script
		visibility_callback = JavaScriptBridge.create_callback(_on_web_visibility_change)
		
		# Hook it into the browser's native 'visibilitychange' event listener
		var document = JavaScriptBridge.get_interface("document")
		document.addEventListener("visibilitychange", visibility_callback)

func _on_web_visibility_change(args):
	var document = JavaScriptBridge.get_interface("document")
	if document.hidden:
		print("Browser tab hidden! Muting audio.")
		AudioServer.set_bus_mute(0, true) # Mutes the Master audio bus
	else:
		print("Browser tab visible! Unmuting audio.")
		AudioServer.set_bus_mute(0, false) # Unmutes the Master audio bus
