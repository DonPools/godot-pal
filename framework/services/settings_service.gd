class_name SettingsService
extends Node

const DEFAULT_PATH := "user://settings.cfg"
const INPUT_BINDINGS_VERSION := 3
const SUPPORTED_LOCALES := [&"zh_CN", &"en"]
const DISPLAY_MODE_WINDOW_2X := &"window_2x"
const DISPLAY_MODE_WINDOW_3X := &"window_3x"
const DISPLAY_MODE_FULLSCREEN := &"fullscreen"
const SUPPORTED_DISPLAY_MODES: Array[StringName] = [
	DISPLAY_MODE_WINDOW_2X,
	DISPLAY_MODE_WINDOW_3X,
	DISPLAY_MODE_FULLSCREEN,
]
const WINDOWED_DISPLAY_SIZES := {
	DISPLAY_MODE_WINDOW_2X: Vector2i(1280, 720),
	DISPLAY_MODE_WINDOW_3X: Vector2i(1920, 1080),
}
const REBINDABLE_ACTIONS: Array[StringName] = InputBindingRegistry.REBINDABLE_ACTIONS
const DEFAULT_MOVEMENT_DEADZONE := 0.18
const DEFAULT_AIM_DEADZONE := 0.25
const DEFAULT_AIM_SENSITIVITY := 1.0
const MIN_STICK_DEADZONE := 0.05
const MAX_STICK_DEADZONE := 0.65
const MIN_AIM_SENSITIVITY := 0.5
const MAX_AIM_SENSITIVITY := 2.0
const DEFAULT_DIALOGUE_TEXT_SPEED := 48.0
const MIN_DIALOGUE_TEXT_SPEED := 24.0
const MAX_DIALOGUE_TEXT_SPEED := 120.0

enum BindingSlot {
	KEYBOARD,
	MOUSE,
	GAMEPAD,
}

var settings_path: String = DEFAULT_PATH
var locale: StringName = &"zh_CN"
var display_mode: StringName = DISPLAY_MODE_WINDOW_2X
var movement_deadzone: float = DEFAULT_MOVEMENT_DEADZONE
var aim_deadzone: float = DEFAULT_AIM_DEADZONE
var aim_sensitivity: float = DEFAULT_AIM_SENSITIVITY
var dialogue_text_speed: float = DEFAULT_DIALOGUE_TEXT_SPEED
var reduce_combat_flashes: bool = false
var last_diagnostic: Dictionary = {}

var _audio_service: AudioService
var _last_windowed_display_mode: StringName = DISPLAY_MODE_WINDOW_2X
var _input_bindings := InputBindingRegistry.new()


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
	_last_windowed_display_mode = _validated_windowed_display_mode(
		StringName(
			config.get_value(
				"display", "windowed_mode", String(DISPLAY_MODE_WINDOW_2X)
			)
		)
	)
	set_display_mode(
		StringName(
			config.get_value("display", "window_mode", String(DISPLAY_MODE_WINDOW_2X))
		),
		false
	)
	set_input_tuning(
		float(config.get_value("input", "movement_deadzone", DEFAULT_MOVEMENT_DEADZONE)),
		float(config.get_value("input", "aim_deadzone", DEFAULT_AIM_DEADZONE)),
		float(config.get_value("input", "aim_sensitivity", DEFAULT_AIM_SENSITIVITY)),
		false
	)
	set_accessibility(
		float(
			config.get_value(
				"accessibility", "dialogue_text_speed", DEFAULT_DIALOGUE_TEXT_SPEED
			)
		),
		bool(config.get_value("accessibility", "reduce_combat_flashes", false)),
		false
	)
	var input_bindings_version := int(config.get_value("input", "version", 1))
	if input_bindings_version >= INPUT_BINDINGS_VERSION:
		_input_bindings.load_section(
			config, "input_keyboard", InputBindingCodec.Device.KEYBOARD
		)
		_input_bindings.load_section(
			config, "input_mouse", InputBindingCodec.Device.MOUSE
		)
		_input_bindings.load_section(
			config, "input_gamepad", InputBindingCodec.Device.GAMEPAD
		)
	else:
		_input_bindings.load_legacy_keyboard_bindings(config, input_bindings_version)
	_input_bindings.ensure_secondary()


func save_settings() -> Error:
	var config := ConfigFile.new()
	config.set_value("audio", "music_enabled", music_enabled())
	config.set_value("audio", "sound_enabled", sound_enabled())
	config.set_value("display", "locale", String(locale))
	config.set_value("display", "window_mode", String(display_mode))
	config.set_value(
		"display", "windowed_mode", String(_last_windowed_display_mode)
	)
	config.set_value("input", "version", INPUT_BINDINGS_VERSION)
	config.set_value("input", "movement_deadzone", movement_deadzone)
	config.set_value("input", "aim_deadzone", aim_deadzone)
	config.set_value("input", "aim_sensitivity", aim_sensitivity)
	config.set_value("accessibility", "dialogue_text_speed", dialogue_text_speed)
	config.set_value("accessibility", "reduce_combat_flashes", reduce_combat_flashes)
	for action: StringName in REBINDABLE_ACTIONS:
		config.set_value(
			"input_keyboard",
			String(action),
			InputBindingCodec.encode(binding_event(action, BindingSlot.KEYBOARD))
		)
		config.set_value(
			"input_mouse",
			String(action),
			InputBindingCodec.encode(binding_event(action, BindingSlot.MOUSE))
		)
		config.set_value(
			"input_gamepad",
			String(action),
			InputBindingCodec.encode(binding_event(action, BindingSlot.GAMEPAD))
		)
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


func set_display_mode(value: StringName, persist: bool = true) -> void:
	display_mode = (
		value if value in SUPPORTED_DISPLAY_MODES else DISPLAY_MODE_WINDOW_2X
	)
	if display_mode != DISPLAY_MODE_FULLSCREEN:
		_last_windowed_display_mode = display_mode
	_apply_display_mode()
	if persist:
		save_settings()


func toggle_fullscreen(persist: bool = true) -> void:
	var fullscreen := display_mode == DISPLAY_MODE_FULLSCREEN
	if DisplayServer.get_name() != "headless" and is_inside_tree():
		fullscreen = fullscreen or _window_is_fullscreen(get_window())
	set_display_mode(
		_last_windowed_display_mode if fullscreen else DISPLAY_MODE_FULLSCREEN,
		persist
	)


func set_key_binding(action: StringName, keycode: Key, persist: bool = true) -> bool:
	var replacement := InputEventKey.new()
	replacement.physical_keycode = keycode
	return set_input_binding(action, BindingSlot.KEYBOARD, replacement, persist)


func set_input_binding(
	action: StringName,
	slot: BindingSlot,
	event: InputEvent,
	persist: bool = true
) -> bool:
	var device := _binding_device(slot)
	var changed := _input_bindings.set_binding(action, device, event)
	if changed and persist:
		save_settings()
	return changed


func clear_input_binding(
	action: StringName,
	slot: BindingSlot,
	persist: bool = true
) -> bool:
	var device := _binding_device(slot)
	var changed := _input_bindings.clear_binding(action, device, persist)
	if changed and persist:
		save_settings()
	return changed


func reset_input_bindings(persist: bool = true) -> void:
	_input_bindings.reset()
	set_input_tuning(
		DEFAULT_MOVEMENT_DEADZONE,
		DEFAULT_AIM_DEADZONE,
		DEFAULT_AIM_SENSITIVITY,
		false
	)
	if persist:
		save_settings()


func set_input_tuning(
	new_movement_deadzone: float,
	new_aim_deadzone: float,
	new_aim_sensitivity: float,
	persist: bool = true
) -> void:
	movement_deadzone = clampf(
		new_movement_deadzone, MIN_STICK_DEADZONE, MAX_STICK_DEADZONE
	)
	aim_deadzone = clampf(new_aim_deadzone, MIN_STICK_DEADZONE, MAX_STICK_DEADZONE)
	aim_sensitivity = clampf(
		new_aim_sensitivity, MIN_AIM_SENSITIVITY, MAX_AIM_SENSITIVITY
	)
	for action: StringName in [&"move_north", &"move_south", &"move_west", &"move_east"]:
		if InputMap.has_action(action):
			InputMap.action_set_deadzone(action, movement_deadzone)
	for action: StringName in [&"aim_north", &"aim_south", &"aim_west", &"aim_east"]:
		if InputMap.has_action(action):
			InputMap.action_set_deadzone(action, aim_deadzone)
	if persist:
		save_settings()


func set_accessibility(
	new_dialogue_text_speed: float,
	new_reduce_combat_flashes: bool,
	persist: bool = true
) -> void:
	dialogue_text_speed = clampf(
		new_dialogue_text_speed,
		MIN_DIALOGUE_TEXT_SPEED,
		MAX_DIALOGUE_TEXT_SPEED
	)
	reduce_combat_flashes = new_reduce_combat_flashes
	if persist:
		save_settings()


func binding_event(action: StringName, slot: BindingSlot) -> InputEvent:
	return _input_bindings.binding_event(action, _binding_device(slot))


func binding_label(action: StringName, slot: BindingSlot) -> String:
	return _input_bindings.binding_label(action, _binding_device(slot))


func conflicting_action(
	action: StringName,
	slot: BindingSlot,
	event: InputEvent
) -> StringName:
	return _input_bindings.conflicting_action(action, _binding_device(slot), event)


func key_for_action(action: StringName) -> Key:
	return _input_bindings.key_for_action(action)


func key_label(action: StringName) -> String:
	return _input_bindings.key_label(action)


func _binding_device(slot: BindingSlot) -> InputBindingCodec.Device:
	match slot:
		BindingSlot.KEYBOARD:
			return InputBindingCodec.Device.KEYBOARD
		BindingSlot.MOUSE:
			return InputBindingCodec.Device.MOUSE
		BindingSlot.GAMEPAD:
			return InputBindingCodec.Device.GAMEPAD
	return InputBindingCodec.Device.KEYBOARD


func _apply_audio(music: bool, sound: bool) -> void:
	if _audio_service != null:
		_audio_service.set_music_enabled(music)
		_audio_service.set_sound_enabled(sound)


func _validated_windowed_display_mode(value: StringName) -> StringName:
	return value if value in WINDOWED_DISPLAY_SIZES else DISPLAY_MODE_WINDOW_2X


func _apply_display_mode() -> void:
	if DisplayServer.get_name() == "headless" or not is_inside_tree():
		return
	var window := get_window()
	if display_mode == DISPLAY_MODE_FULLSCREEN:
		window.mode = Window.MODE_FULLSCREEN
		return
	var was_fullscreen := _window_is_fullscreen(window)
	window.mode = Window.MODE_WINDOWED
	var target_size: Vector2i = WINDOWED_DISPLAY_SIZES.get(
		display_mode, WINDOWED_DISPLAY_SIZES[DISPLAY_MODE_WINDOW_2X]
	)
	if was_fullscreen:
		call_deferred("_apply_windowed_size", target_size)
	else:
		_apply_windowed_size(target_size)


func _apply_windowed_size(target_size: Vector2i) -> void:
	if DisplayServer.get_name() == "headless" or not is_inside_tree():
		return
	get_window().size = target_size


func _window_is_fullscreen(window: Window) -> bool:
	return window.mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]
