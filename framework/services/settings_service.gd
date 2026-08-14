class_name SettingsService
extends Node

const DEFAULT_PATH := "user://settings.cfg"
const SUPPORTED_LOCALES := [&"zh_CN", &"en"]
const REBINDABLE_ACTIONS := [
	&"move_north", &"move_south", &"move_west", &"move_east", &"interact", &"menu",
]

var settings_path: String = DEFAULT_PATH
var locale: StringName = &"zh_CN"
var last_diagnostic: Dictionary = {}

var _audio_service: AudioService


func configure(audio_service: AudioService, path: String = DEFAULT_PATH) -> void:
	_audio_service = audio_service
	settings_path = path
	load_settings()


func load_settings() -> void:
	last_diagnostic.clear()
	var config := ConfigFile.new()
	var error := config.load(settings_path)
	if error != OK and error != ERR_FILE_NOT_FOUND:
		last_diagnostic = {
			"code": "settings_load_failed",
			"message": error_string(error),
			"file": settings_path,
		}
	_apply_audio(
		bool(config.get_value("audio", "music_enabled", true)),
		bool(config.get_value("audio", "sound_enabled", true))
	)
	set_locale(StringName(config.get_value("display", "locale", "zh_CN")), false)
	for action: StringName in REBINDABLE_ACTIONS:
		if not config.has_section_key("input", String(action)):
			continue
		var raw_key: Variant = config.get_value("input", String(action))
		if raw_key is int and int(raw_key) > 0:
			set_key_binding(action, int(raw_key) as Key, false)


func save_settings() -> Error:
	var config := ConfigFile.new()
	config.set_value("audio", "music_enabled", music_enabled())
	config.set_value("audio", "sound_enabled", sound_enabled())
	config.set_value("display", "locale", String(locale))
	for action: StringName in REBINDABLE_ACTIONS:
		config.set_value("input", String(action), int(key_for_action(action)))
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(settings_path.get_base_dir())
	)
	if directory_error != OK:
		return directory_error
	var error := config.save(settings_path)
	if error != OK:
		last_diagnostic = {
			"code": "settings_save_failed",
			"message": error_string(error),
			"file": settings_path,
		}
	return error


func set_music_enabled(enabled: bool, persist: bool = true) -> void:
	if _audio_service != null:
		_audio_service.set_music_enabled(enabled)
	if persist:
		save_settings()


func set_sound_enabled(enabled: bool, persist: bool = true) -> void:
	if _audio_service != null:
		_audio_service.set_sound_enabled(enabled)
	if persist:
		save_settings()


func music_enabled() -> bool:
	return _audio_service == null or _audio_service.music_enabled


func sound_enabled() -> bool:
	return _audio_service == null or _audio_service.sound_enabled


func set_locale(value: StringName, persist: bool = true) -> void:
	locale = value if value in SUPPORTED_LOCALES else &"zh_CN"
	TranslationServer.set_locale(String(locale))
	if persist:
		save_settings()


func set_key_binding(action: StringName, keycode: Key, persist: bool = true) -> bool:
	if action not in REBINDABLE_ACTIONS or keycode == KEY_NONE:
		return false
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey:
			InputMap.action_erase_event(action, event)
	var replacement := InputEventKey.new()
	replacement.physical_keycode = keycode
	InputMap.action_add_event(action, replacement)
	if persist:
		save_settings()
	return true


func key_for_action(action: StringName) -> Key:
	if not InputMap.has_action(action):
		return KEY_NONE
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key_event := event as InputEventKey
			return key_event.physical_keycode if key_event.physical_keycode != KEY_NONE else key_event.keycode
	return KEY_NONE


func key_label(action: StringName) -> String:
	var keycode := key_for_action(action)
	return OS.get_keycode_string(keycode) if keycode != KEY_NONE else "—"


func _apply_audio(music: bool, sound: bool) -> void:
	if _audio_service != null:
		_audio_service.set_music_enabled(music)
		_audio_service.set_sound_enabled(sound)
