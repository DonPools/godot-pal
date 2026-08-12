class_name AudioService
extends Node

@onready var _music_player: AudioStreamPlayer = $MusicPlayer
@onready var _sound_player: AudioStreamPlayer = $SoundPlayer

var _assets: AssetLibrary
var _current_music_source: int = -1
var _requested_music_source: int = -1
var _output_enabled: bool = true
var music_enabled: bool = true
var sound_enabled: bool = true


func configure(assets: AssetLibrary) -> void:
	_assets = assets
	_output_enabled = DisplayServer.get_name() != "headless"


func play_music(source_id: int) -> void:
	_requested_music_source = source_id
	if not _output_enabled or not music_enabled or _assets == null or _current_music_source == source_id:
		return
	var stream := _assets.music(source_id)
	if stream == null:
		return
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_music_player.stream = stream
	_music_player.play()
	_current_music_source = source_id


func play_sound(source_id: int) -> void:
	if not _output_enabled or not sound_enabled or _assets == null:
		return
	var stream := _assets.sound(source_id)
	if stream == null:
		return
	_sound_player.stream = stream
	_sound_player.play()


func set_music_enabled(enabled: bool) -> void:
	music_enabled = enabled
	if is_instance_valid(_music_player):
		_music_player.stream_paused = not enabled
	if enabled and _requested_music_source >= 0 and _requested_music_source != _current_music_source:
		play_music(_requested_music_source)


func set_sound_enabled(enabled: bool) -> void:
	sound_enabled = enabled
	if not enabled and is_instance_valid(_sound_player):
		_sound_player.stop()


func shutdown() -> void:
	_music_player.stop()
	_sound_player.stop()
	_music_player.stream = null
	_sound_player.stream = null
	_current_music_source = -1
	_requested_music_source = -1
