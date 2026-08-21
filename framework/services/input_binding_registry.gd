class_name InputBindingRegistry
extends RefCounted

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
	&"menu": KEY_ESCAPE,
	&"combat_skill_two": KEY_1,
	&"combat_skill_three": KEY_2,
	&"combat_dodge": KEY_SPACE,
	&"combat_item": KEY_Q,
	&"combat_stand_ground": KEY_SHIFT,
	&"combat_force_move": KEY_CTRL,
	&"combat_target_next": KEY_TAB,
}
const SECONDARY_KEY_BINDINGS := {
	&"move_north": [KEY_UP],
	&"move_south": [KEY_DOWN],
	&"move_west": [KEY_LEFT],
	&"move_east": [KEY_RIGHT],
	&"menu": [KEY_M],
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


func set_binding(
	action: StringName,
	device: InputBindingCodec.Device,
	event: InputEvent
) -> bool:
	if (
		action not in REBINDABLE_ACTIONS
		or not InputBindingCodec.event_matches_device(event, device)
	):
		return false
	_ensure_action(action)
	clear_binding(action, device, false)
	InputMap.action_add_event(action, InputBindingCodec.normalized_event(event, device))
	if device == InputBindingCodec.Device.KEYBOARD:
		ensure_secondary(action)
	return true


func clear_binding(
	action: StringName,
	device: InputBindingCodec.Device,
	restore_secondary: bool
) -> bool:
	if action not in REBINDABLE_ACTIONS or not InputMap.has_action(action):
		return false
	for event: InputEvent in InputMap.action_get_events(action):
		if InputBindingCodec.event_matches_device(event, device):
			InputMap.action_erase_event(action, event)
	if restore_secondary and device == InputBindingCodec.Device.KEYBOARD:
		ensure_secondary(action)
	return true


func reset() -> void:
	for action: StringName in REBINDABLE_ACTIONS:
		_ensure_action(action)
		clear_binding(action, InputBindingCodec.Device.KEYBOARD, false)
		clear_binding(action, InputBindingCodec.Device.MOUSE, false)
		clear_binding(action, InputBindingCodec.Device.GAMEPAD, false)
	for action: StringName in DEFAULT_KEY_BINDINGS:
		var key_event := InputEventKey.new()
		key_event.physical_keycode = DEFAULT_KEY_BINDINGS[action] as Key
		InputMap.action_add_event(action, key_event)
	for action: StringName in SECONDARY_KEY_BINDINGS:
		for key: Key in SECONDARY_KEY_BINDINGS[action]:
			var secondary_event := InputEventKey.new()
			secondary_event.physical_keycode = key
			InputMap.action_add_event(action, secondary_event)
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


func binding_event(action: StringName, device: InputBindingCodec.Device) -> InputEvent:
	if not InputMap.has_action(action):
		return null
	for event: InputEvent in InputMap.action_get_events(action):
		if InputBindingCodec.event_matches_device(event, device):
			return event
	return null


func binding_label(action: StringName, device: InputBindingCodec.Device) -> String:
	var event := binding_event(action, device)
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


func conflicting_action(
	action: StringName,
	device: InputBindingCodec.Device,
	event: InputEvent
) -> StringName:
	if (
		action not in REBINDABLE_ACTIONS
		or not InputBindingCodec.event_matches_device(event, device)
	):
		return &""
	var candidate := InputBindingCodec.encode(
		InputBindingCodec.normalized_event(event, device)
	)
	for other_action: StringName in REBINDABLE_ACTIONS:
		if other_action == action or not InputMap.has_action(other_action):
			continue
		for existing: InputEvent in InputMap.action_get_events(other_action):
			if (
				InputBindingCodec.event_matches_device(existing, device)
				and InputBindingCodec.encode(existing) == candidate
			):
				return other_action
	return &""


func key_for_action(action: StringName) -> Key:
	var event := binding_event(action, InputBindingCodec.Device.KEYBOARD)
	if not event is InputEventKey:
		return KEY_NONE
	var key_event := event as InputEventKey
	return (
		key_event.physical_keycode
		if key_event.physical_keycode != KEY_NONE
		else key_event.keycode
	)


func key_label(action: StringName) -> String:
	var keyboard := binding_label(action, InputBindingCodec.Device.KEYBOARD)
	return (
		keyboard
		if keyboard != "—"
		else binding_label(action, InputBindingCodec.Device.MOUSE)
	)


func load_legacy_keyboard_bindings(config: ConfigFile, version: int) -> void:
	for action: StringName in REBINDABLE_ACTIONS:
		if not config.has_section_key("input", String(action)):
			continue
		var raw_key: Variant = config.get_value("input", String(action))
		if version < 2 and LEGACY_ARPG_DEFAULT_KEYS.get(action, KEY_NONE) == raw_key:
			continue
		if raw_key is int and int(raw_key) > 0:
			var key_event := InputEventKey.new()
			key_event.physical_keycode = int(raw_key) as Key
			set_binding(action, InputBindingCodec.Device.KEYBOARD, key_event)


func load_section(
	config: ConfigFile,
	section: String,
	device: InputBindingCodec.Device
) -> void:
	for action: StringName in REBINDABLE_ACTIONS:
		if not config.has_section_key(section, String(action)):
			continue
		var event := InputBindingCodec.decode(
			String(config.get_value(section, String(action), "")),
			device
		)
		if event == null:
			clear_binding(action, device, false)
		else:
			set_binding(action, device, event)


func ensure_secondary(action_filter: StringName = &"") -> void:
	for action: StringName in SECONDARY_KEY_BINDINGS:
		if not action_filter.is_empty() and action != action_filter:
			continue
		_ensure_action(action)
		for key: Key in SECONDARY_KEY_BINDINGS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			if not InputMap.action_has_event(action, event):
				InputMap.action_add_event(action, event)


func _ensure_action(action: StringName) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)


func _mouse_button_label(button: MouseButton) -> String:
	match button:
		MOUSE_BUTTON_LEFT:
			return tr("UI_INPUT_MOUSE_LEFT")
		MOUSE_BUTTON_RIGHT:
			return tr("UI_INPUT_MOUSE_RIGHT")
		MOUSE_BUTTON_MIDDLE:
			return tr("UI_INPUT_MOUSE_MIDDLE")
		MOUSE_BUTTON_WHEEL_UP:
			return tr("UI_INPUT_WHEEL_UP")
		MOUSE_BUTTON_WHEEL_DOWN:
			return tr("UI_INPUT_WHEEL_DOWN")
	return tr("UI_INPUT_MOUSE_FORMAT") % int(button)


func _joypad_button_label(button: JoyButton) -> String:
	var labels := {
		JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
		JOY_BUTTON_BACK: "Back", JOY_BUTTON_GUIDE: "Guide", JOY_BUTTON_START: "Start",
		JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
		JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
		JOY_BUTTON_DPAD_UP: tr("UI_INPUT_DPAD_UP"),
		JOY_BUTTON_DPAD_DOWN: tr("UI_INPUT_DPAD_DOWN"),
		JOY_BUTTON_DPAD_LEFT: tr("UI_INPUT_DPAD_LEFT"),
		JOY_BUTTON_DPAD_RIGHT: tr("UI_INPUT_DPAD_RIGHT"),
	}
	return labels.get(button, tr("UI_INPUT_GAMEPAD_FORMAT") % int(button))


func _joypad_axis_label(axis: JoyAxis) -> String:
	var labels := {
		JOY_AXIS_LEFT_X: tr("UI_INPUT_LEFT_STICK_X"),
		JOY_AXIS_LEFT_Y: tr("UI_INPUT_LEFT_STICK_Y"),
		JOY_AXIS_RIGHT_X: tr("UI_INPUT_RIGHT_STICK_X"),
		JOY_AXIS_RIGHT_Y: tr("UI_INPUT_RIGHT_STICK_Y"),
		JOY_AXIS_TRIGGER_LEFT: "LT", JOY_AXIS_TRIGGER_RIGHT: "RT",
	}
	return labels.get(axis, tr("UI_INPUT_AXIS_FORMAT") % int(axis))
