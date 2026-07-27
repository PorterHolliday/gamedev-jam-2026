extends Node

## Owns every audio stream in the game and all playback policy.
##
## Callers ask for a named track ([method crossfade_to_level_music]) rather than
## passing a stream in, so no other node needs to hold music resources.

const MUSIC_DB: float = -20.0
const SFX_PLAYER_POOL_COUNT: int = 5
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

@onready var music_player_a: AudioStreamPlayer = AudioStreamPlayer.new()
@onready var music_player_b: AudioStreamPlayer = AudioStreamPlayer.new()

var sfx_player_pool: Array[AudioStreamPlayer] = []

func _ready() -> void:
	add_child(music_player_a)
	music_player_a.bus = 'Music'
	music_player_a.volume_db = MUSIC_DB
	add_child(music_player_b)
	music_player_b.bus = 'Music'
	music_player_b.volume_db = MUSIC_DB
	for i in range(SFX_PLAYER_POOL_COUNT):
		var sfx_player: AudioStreamPlayer = AudioStreamPlayer.new()
		sfx_player_pool.append(sfx_player)
		add_child(sfx_player)
		sfx_player.bus = 'SFX'
	# Not awaited: startup must not block on this.
	_warm_up_music()

#region Music

func play_menu_music() -> void:
	_play_music(menu_music)

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
	tween.tween_property(inactive_music_player, 'volume_linear', db_to_linear(MUSIC_DB), duration)
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
	var player: AudioStreamPlayer = play_sfx(button_click_sfx, 0.17)
	await get_tree().create_timer(0.4).timeout
	player.stop()
	
func play_connection_sfx() -> void:
	var player: AudioStreamPlayer = play_sfx(connection_sfx, 0.12)
	await get_tree().create_timer(0.2).timeout
	player.stop()
	
func play_disconnection_sfx() -> void:
	var player: AudioStreamPlayer = play_sfx(disconnection_sfx, 0.35)
	await get_tree().create_timer(0.1).timeout
	player.stop()
	
func play_grab_sfx() -> void:
	var player: AudioStreamPlayer = play_sfx(grab_sfx, 0.02)
	player.volume_db = -10.0
	await get_tree().create_timer(0.1).timeout
	player.volume_linear = 1.0
	player.stop()
	
func play_drop_sfx() -> void:
	var player: AudioStreamPlayer = play_sfx(drop_sfx, 0.02)
	player.volume_db = -10.0
	player.pitch_scale = 0.7
	await get_tree().create_timer(0.1).timeout
	player.volume_linear = 1.0
	player.pitch_scale = 1.0
	player.stop()
	
func play_output_satisfied_sfx() -> void:
	var player: AudioStreamPlayer = play_sfx(output_satisfied_sfx, 0.13)
	player.volume_db += 5.0
	await get_tree().create_timer(0.1).timeout
	player.volume_db -= 5.0
	player.stop()
	
func _get_sfx_player() -> AudioStreamPlayer:
	for sfx_player in sfx_player_pool:
		if sfx_player.playing: continue
		return sfx_player
	# Pool exhausted: steal the oldest rather than returning null, which every
	# caller would dereference immediately.
	return sfx_player_pool[0]

#endregion
