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
const REBINDABLE_ACTIONS: Array[StringName] = [
	&"move_north", &"move_south", &"move_west", &"move_east",
	&"aim_north", &"aim_south", &"aim_west", &"aim_east",
	&"interact", &"menu", &"combat_attack", &"combat_skill_one",
	&"combat_skill_two", &"combat_skill_three", &"combat_dodge", &"combat_item",
	&"combat_stand_ground", &"combat_force_move", &"combat_target_next",
]
const DEFAULT_KEY_BINDINGS := {
	&"move_north": KEY_W,
	&"move_south": KEY_S,
	&"move_west": KEY_A,
	&"move_east": KEY_D,
	&"interact": KEY_ENTER,
	&"menu": KEY_M,
	&"combat_skill_two": KEY_1,
	&"combat_skill_three": KEY_2,
	&"combat_dodge": KEY_SPACE,
	&"combat_item": KEY_Q,
	&"combat_stand_ground": KEY_SHIFT,
	&"combat_force_move": KEY_CTRL,
	&"combat_target_next": KEY_TAB,
}
const DEFAULT_MOUSE_BINDINGS := {
	&"combat_attack": MOUSE_BUTTON_LEFT,
	&"combat_skill_one": MOUSE_BUTTON_RIGHT,
}
const DEFAULT_GAMEPAD_BUTTON_BINDINGS := {
	&"interact": JOY_BUTTON_A,
	&"menu": JOY_BUTTON_START,
	&"combat_attack": JOY_BUTTON_A,
	&"combat_skill_one": JOY_BUTTON_X,
	&"combat_skill_two": JOY_BUTTON_Y,
	&"combat_skill_three": JOY_BUTTON_RIGHT_SHOULDER,
	&"combat_dodge": JOY_BUTTON_B,
	&"combat_item": JOY_BUTTON_LEFT_SHOULDER,
	&"combat_target_next": JOY_BUTTON_RIGHT_STICK,
}
const DEFAULT_GAMEPAD_AXIS_BINDINGS := {
	&"move_west": [JOY_AXIS_LEFT_X, -1.0],
	&"move_east": [JOY_AXIS_LEFT_X, 1.0],
	&"move_north": [JOY_AXIS_LEFT_Y, -1.0],
	&"move_south": [JOY_AXIS_LEFT_Y, 1.0],
	&"aim_west": [JOY_AXIS_RIGHT_X, -1.0],
	&"aim_east": [JOY_AXIS_RIGHT_X, 1.0],
	&"aim_north": [JOY_AXIS_RIGHT_Y, -1.0],
	&"aim_south": [JOY_AXIS_RIGHT_Y, 1.0],
}
const LEGACY_ARPG_DEFAULT_KEYS := {
	&"combat_skill_one": KEY_Q,
	&"combat_skill_two": KEY_E,
	&"combat_skill_three": KEY_F,
	&"combat_item": KEY_R,
}
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
		_load_binding_section(config, "input_keyboard", BindingSlot.KEYBOARD)
		_load_binding_section(config, "input_mouse", BindingSlot.MOUSE)
		_load_binding_section(config, "input_gamepad", BindingSlot.GAMEPAD)
	else:
		_load_legacy_keyboard_bindings(config, input_bindings_version)


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
			_encode_binding(binding_event(action, BindingSlot.KEYBOARD))
		)
		config.set_value(
			"input_mouse",
			String(action),
			_encode_binding(binding_event(action, BindingSlot.MOUSE))
		)
		config.set_value(
			"input_gamepad",
			String(action),
			_encode_binding(binding_event(action, BindingSlot.GAMEPAD))
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
	if action not in REBINDABLE_ACTIONS or not _event_matches_slot(event, slot):
		return false
	_ensure_action(action)
	clear_input_binding(action, slot, false)
	InputMap.action_add_event(action, _normalized_binding_event(event, slot))
	if persist:
		save_settings()
	return true


func clear_input_binding(
	action: StringName,
	slot: BindingSlot,
	persist: bool = true
) -> bool:
	if action not in REBINDABLE_ACTIONS or not InputMap.has_action(action):
		return false
	for event: InputEvent in InputMap.action_get_events(action):
		if _event_matches_slot(event, slot):
			InputMap.action_erase_event(action, event)
	if persist:
		save_settings()
	return true


func reset_input_bindings(persist: bool = true) -> void:
	for action: StringName in REBINDABLE_ACTIONS:
		_ensure_action(action)
		clear_input_binding(action, BindingSlot.KEYBOARD, false)
		clear_input_binding(action, BindingSlot.MOUSE, false)
		clear_input_binding(action, BindingSlot.GAMEPAD, false)
	for action: StringName in DEFAULT_KEY_BINDINGS:
		var key_event := InputEventKey.new()
		key_event.physical_keycode = DEFAULT_KEY_BINDINGS[action] as Key
		InputMap.action_add_event(action, key_event)
	for action: StringName in DEFAULT_MOUSE_BINDINGS:
		var mouse_event := InputEventMouseButton.new()
		mouse_event.button_index = DEFAULT_MOUSE_BINDINGS[action] as MouseButton
		InputMap.action_add_event(action, mouse_event)
	for action: StringName in DEFAULT_GAMEPAD_BUTTON_BINDINGS:
		var button_event := InputEventJoypadButton.new()
		button_event.button_index = DEFAULT_GAMEPAD_BUTTON_BINDINGS[action] as JoyButton
		InputMap.action_add_event(action, button_event)
	for action: StringName in DEFAULT_GAMEPAD_AXIS_BINDINGS:
		var axis_binding: Array = DEFAULT_GAMEPAD_AXIS_BINDINGS[action]
		var axis_event := InputEventJoypadMotion.new()
		axis_event.axis = axis_binding[0] as JoyAxis
		axis_event.axis_value = float(axis_binding[1])
		InputMap.action_add_event(action, axis_event)
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
	if not InputMap.has_action(action):
		return null
	for event: InputEvent in InputMap.action_get_events(action):
		if _event_matches_slot(event, slot):
			return event
	return null


func binding_label(action: StringName, slot: BindingSlot) -> String:
	var event := binding_event(action, slot)
	if event == null:
		return "—"
	if event is InputEventKey:
		var key_event := event as InputEventKey
		var keycode := (
			key_event.physical_keycode
			if key_event.physical_keycode != KEY_NONE
			else key_event.keycode
		)
		return OS.get_keycode_string(keycode)
	if event is InputEventMouseButton:
		return _mouse_button_label((event as InputEventMouseButton).button_index)
	if event is InputEventJoypadButton:
		return _joypad_button_label((event as InputEventJoypadButton).button_index)
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		return "%s%s" % [
			_joypad_axis_label(motion.axis),
			"−" if motion.axis_value < 0.0 else "+",
		]
	return "—"


func key_for_action(action: StringName) -> Key:
	if not InputMap.has_action(action):
		return KEY_NONE
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key_event := event as InputEventKey
			return key_event.physical_keycode if key_event.physical_keycode != KEY_NONE else key_event.keycode
	return KEY_NONE


func key_label(action: StringName) -> String:
	var keyboard := binding_label(action, BindingSlot.KEYBOARD)
	return keyboard if keyboard != "—" else binding_label(action, BindingSlot.MOUSE)


func _load_legacy_keyboard_bindings(config: ConfigFile, version: int) -> void:
	for action: StringName in REBINDABLE_ACTIONS:
		if not config.has_section_key("input", String(action)):
			continue
		var raw_key: Variant = config.get_value("input", String(action))
		if version < 2 and LEGACY_ARPG_DEFAULT_KEYS.get(action, KEY_NONE) == raw_key:
			continue
		if raw_key is int and int(raw_key) > 0:
			set_key_binding(action, int(raw_key) as Key, false)


func _load_binding_section(
	config: ConfigFile,
	section: String,
	slot: BindingSlot
) -> void:
	for action: StringName in REBINDABLE_ACTIONS:
		if not config.has_section_key(section, String(action)):
			continue
		var event := _decode_binding(String(config.get_value(section, String(action), "")), slot)
		if event == null:
			clear_input_binding(action, slot, false)
		else:
			set_input_binding(action, slot, event, false)


func _encode_binding(event: InputEvent) -> String:
	if event == null:
		return ""
	if event is InputEventKey:
		var key_event := event as InputEventKey
		var keycode := (
			key_event.physical_keycode
			if key_event.physical_keycode != KEY_NONE
			else key_event.keycode
		)
		return "key:%d" % int(keycode)
	if event is InputEventMouseButton:
		return "mouse:%d" % int((event as InputEventMouseButton).button_index)
	if event is InputEventJoypadButton:
		return "button:%d" % int((event as InputEventJoypadButton).button_index)
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		return "axis:%d:%d" % [int(motion.axis), -1 if motion.axis_value < 0.0 else 1]
	return ""


func _decode_binding(encoded: String, slot: BindingSlot) -> InputEvent:
	if encoded.is_empty():
		return null
	var parts := encoded.split(":")
	if parts.size() < 2:
		return null
	match slot:
		BindingSlot.KEYBOARD:
			if parts[0] != "key":
				return null
			var key_event := InputEventKey.new()
			key_event.physical_keycode = int(parts[1]) as Key
			return key_event
		BindingSlot.MOUSE:
			if parts[0] != "mouse":
				return null
			var mouse_event := InputEventMouseButton.new()
			mouse_event.button_index = int(parts[1]) as MouseButton
			return mouse_event
		BindingSlot.GAMEPAD:
			if parts[0] == "button":
				var button_event := InputEventJoypadButton.new()
				button_event.button_index = int(parts[1]) as JoyButton
				return button_event
			if parts[0] == "axis" and parts.size() == 3:
				var axis_event := InputEventJoypadMotion.new()
				axis_event.axis = int(parts[1]) as JoyAxis
				axis_event.axis_value = -1.0 if int(parts[2]) < 0 else 1.0
				return axis_event
	return null


func _event_matches_slot(event: InputEvent, slot: BindingSlot) -> bool:
	if event == null:
		return false
	match slot:
		BindingSlot.KEYBOARD:
			return event is InputEventKey
		BindingSlot.MOUSE:
			return event is InputEventMouseButton
		BindingSlot.GAMEPAD:
			return event is InputEventJoypadButton or event is InputEventJoypadMotion
	return false


func _normalized_binding_event(event: InputEvent, slot: BindingSlot) -> InputEvent:
	if slot == BindingSlot.KEYBOARD:
		var source_key := event as InputEventKey
		var key_event := InputEventKey.new()
		key_event.physical_keycode = (
			source_key.physical_keycode
			if source_key.physical_keycode != KEY_NONE
			else source_key.keycode
		)
		return key_event
	if slot == BindingSlot.MOUSE:
		var mouse_event := InputEventMouseButton.new()
		mouse_event.button_index = (event as InputEventMouseButton).button_index
		return mouse_event
	if event is InputEventJoypadButton:
		var button_event := InputEventJoypadButton.new()
		button_event.button_index = (event as InputEventJoypadButton).button_index
		return button_event
	var axis_source := event as InputEventJoypadMotion
	var axis_event := InputEventJoypadMotion.new()
	axis_event.axis = axis_source.axis
	axis_event.axis_value = -1.0 if axis_source.axis_value < 0.0 else 1.0
	return axis_event


func _ensure_action(action: StringName) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)


func _mouse_button_label(button: MouseButton) -> String:
	match button:
		MOUSE_BUTTON_LEFT:
			return "鼠左"
		MOUSE_BUTTON_RIGHT:
			return "鼠右"
		MOUSE_BUTTON_MIDDLE:
			return "鼠中"
		MOUSE_BUTTON_WHEEL_UP:
			return "滚轮上"
		MOUSE_BUTTON_WHEEL_DOWN:
			return "滚轮下"
	return "鼠键 %d" % int(button)


func _joypad_button_label(button: JoyButton) -> String:
	const LABELS := {
		JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
		JOY_BUTTON_BACK: "Back", JOY_BUTTON_GUIDE: "Guide", JOY_BUTTON_START: "Start",
		JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
		JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
		JOY_BUTTON_DPAD_UP: "十字上", JOY_BUTTON_DPAD_DOWN: "十字下",
		JOY_BUTTON_DPAD_LEFT: "十字左", JOY_BUTTON_DPAD_RIGHT: "十字右",
	}
	return LABELS.get(button, "手柄 %d" % int(button))


func _joypad_axis_label(axis: JoyAxis) -> String:
	const LABELS := {
		JOY_AXIS_LEFT_X: "左摇杆 X", JOY_AXIS_LEFT_Y: "左摇杆 Y",
		JOY_AXIS_RIGHT_X: "右摇杆 X", JOY_AXIS_RIGHT_Y: "右摇杆 Y",
		JOY_AXIS_TRIGGER_LEFT: "LT", JOY_AXIS_TRIGGER_RIGHT: "RT",
	}
	return LABELS.get(axis, "轴 %d" % int(axis))


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
