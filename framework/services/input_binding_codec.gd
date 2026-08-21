class_name InputBindingCodec
extends RefCounted

enum Device {
	KEYBOARD,
	MOUSE,
	GAMEPAD,
}


static func encode(event: InputEvent) -> String:
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


static func decode(encoded: String, device: Device) -> InputEvent:
	if encoded.is_empty():
		return null
	var parts := encoded.split(":")
	if parts.size() < 2:
		return null
	match device:
		Device.KEYBOARD:
			if parts[0] != "key":
				return null
			var key_event := InputEventKey.new()
			key_event.physical_keycode = int(parts[1]) as Key
			return key_event
		Device.MOUSE:
			if parts[0] != "mouse":
				return null
			var mouse_event := InputEventMouseButton.new()
			mouse_event.button_index = int(parts[1]) as MouseButton
			return mouse_event
		Device.GAMEPAD:
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


static func event_matches_device(event: InputEvent, device: Device) -> bool:
	if event == null:
		return false
	match device:
		Device.KEYBOARD:
			return event is InputEventKey
		Device.MOUSE:
			return event is InputEventMouseButton
		Device.GAMEPAD:
			return event is InputEventJoypadButton or event is InputEventJoypadMotion
	return false


static func normalized_event(event: InputEvent, device: Device) -> InputEvent:
	if not event_matches_device(event, device):
		return null
	if device == Device.KEYBOARD:
		var source_key := event as InputEventKey
		var key_event := InputEventKey.new()
		key_event.physical_keycode = (
			source_key.physical_keycode
			if source_key.physical_keycode != KEY_NONE
			else source_key.keycode
		)
		return key_event
	if device == Device.MOUSE:
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
