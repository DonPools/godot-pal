class_name AudioService
extends Node

@onready var _music_player: AudioStreamPlayer = $MusicPlayer
@onready var _sound_player: AudioStreamPlayer = $SoundPlayer

var _requested_music: AudioStream
var _output_enabled: bool = true
var music_enabled: bool = true
var sound_enabled: bool = true


func configure() -> void:
	_output_enabled = DisplayServer.get_name() != "headless"


func play_music(stream: AudioStream) -> void:
	_requested_music = stream
	if not _output_enabled or not music_enabled or stream == null:
		_music_player.stop()
		_music_player.stream = null
		return
	if _music_player.stream == stream and _music_player.playing:
		return
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_music_player.stream = stream
	_music_player.play()


func play_sound(stream: AudioStream) -> void:
	if not _output_enabled or not sound_enabled or stream == null:
		return
	_sound_player.stream = stream
	_sound_player.play()


func set_music_enabled(enabled: bool) -> void:
	music_enabled = enabled
	if is_instance_valid(_music_player):
		_music_player.stream_paused = not enabled
	if enabled and _requested_music != null and _music_player.stream != _requested_music:
		play_music(_requested_music)


func set_sound_enabled(enabled: bool) -> void:
	sound_enabled = enabled
	if not enabled and is_instance_valid(_sound_player):
		_sound_player.stop()


func shutdown() -> void:
	_music_player.stop()
	_sound_player.stop()
	_music_player.stream = null
	_sound_player.stream = null
	_requested_music = null
