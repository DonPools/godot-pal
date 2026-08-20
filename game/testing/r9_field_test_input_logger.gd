class_name R9FieldTestInputLogger
extends Node

const FLUSH_EVENT_COUNT := 32
const FLUSH_INTERVAL_MSEC := 250
const FIELD_TEST_PROFILE_PREFIX := "--r9-field-test-profile="

var output_path: String = ""

var _file: FileAccess
var _started_ticks_msec: int = 0
var _last_flush_ticks_msec: int = 0
var _event_index: int = 0
var _pending_flush_events: int = 0


func start(path: String) -> Error:
	if _file != null or path.is_empty():
		return ERR_INVALID_PARAMETER
	if FileAccess.file_exists(path):
		return ERR_ALREADY_EXISTS
	var absolute_path := ProjectSettings.globalize_path(path)
	var directory_error := DirAccess.make_dir_recursive_absolute(
		absolute_path.get_base_dir()
	)
	if directory_error != OK:
		return directory_error
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		return FileAccess.get_open_error()
	output_path = path
	_started_ticks_msec = Time.get_ticks_msec()
	_last_flush_ticks_msec = _started_ticks_msec
	_write_record(_session_record(&"session_start"), true)
	return OK


func stop() -> void:
	if _file == null:
		return
	_write_record(_session_record(&"session_end"), true)
	_file.close()
	_file = null


func _exit_tree() -> void:
	stop()


func _input(event: InputEvent) -> void:
	if _file == null:
		return
	var record := _input_record(event)
	if record.is_empty():
		return
	_event_index += 1
	record["kind"] = "input"
	record["event_index"] = _event_index
	record["elapsed_msec"] = Time.get_ticks_msec() - _started_ticks_msec
	var actions: Array[String] = []
	for action: StringName in InputMap.get_actions():
		if event.is_action(action):
			actions.append(String(action))
	record["actions"] = actions
	_write_record(record)


func _session_record(kind: StringName) -> Dictionary:
	var version := Engine.get_version_info()
	var viewport_size := Vector2i(get_viewport().get_visible_rect().size)
	var window_size := Vector2i(
		int(ProjectSettings.get_setting("display/window/size/window_width_override", 0)),
		int(ProjectSettings.get_setting("display/window/size/window_height_override", 0))
	)
	if DisplayServer.get_name() != "headless":
		window_size = get_window().size
	return {
		"kind": String(kind),
		"elapsed_msec": Time.get_ticks_msec() - _started_ticks_msec,
		"utc": Time.get_datetime_string_from_system(true, false),
		"engine": {
			"major": int(version.get("major", 0)),
			"minor": int(version.get("minor", 0)),
			"status": String(version.get("status", "")),
			"hash": String(version.get("hash", "")),
		},
		"display_driver": DisplayServer.get_name(),
		"rendering_method": RenderingServer.get_current_rendering_method(),
		"video_adapter": RenderingServer.get_video_adapter_name(),
		"field_test_profile": _field_test_profile_argument(),
		"viewport": [viewport_size.x, viewport_size.y],
		"window": [window_size.x, window_size.y],
	}


func _field_test_profile_argument() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(FIELD_TEST_PROFILE_PREFIX):
			return argument.trim_prefix(FIELD_TEST_PROFILE_PREFIX)
	return ""


func _input_record(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var key := event as InputEventKey
		var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
		return {
			"type": "key",
			"device": key.device,
			"pressed": key.pressed,
			"echo": key.echo,
			"physical_keycode": int(key.physical_keycode),
			"keycode": int(key.keycode),
			"label": OS.get_keycode_string(code),
			"shift": key.shift_pressed,
			"ctrl": key.ctrl_pressed,
			"alt": key.alt_pressed,
			"meta": key.meta_pressed,
		}
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		return {
			"type": "mouse_button",
			"device": button.device,
			"pressed": button.pressed,
			"button": int(button.button_index),
			"position": [button.position.x, button.position.y],
			"double_click": button.double_click,
			"shift": button.shift_pressed,
			"ctrl": button.ctrl_pressed,
		}
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		return {
			"type": "mouse_motion",
			"device": motion.device,
			"position": [motion.position.x, motion.position.y],
			"relative": [motion.relative.x, motion.relative.y],
			"button_mask": int(motion.button_mask),
		}
	if event is InputEventJoypadButton:
		var joy_button := event as InputEventJoypadButton
		return {
			"type": "joy_button",
			"device": joy_button.device,
			"pressed": joy_button.pressed,
			"button": int(joy_button.button_index),
			"pressure": joy_button.pressure,
		}
	if event is InputEventJoypadMotion:
		var joy_motion := event as InputEventJoypadMotion
		return {
			"type": "joy_motion",
			"device": joy_motion.device,
			"axis": int(joy_motion.axis),
			"value": joy_motion.axis_value,
		}
	return {}


func _write_record(record: Dictionary, force_flush: bool = false) -> void:
	_file.store_line(JSON.stringify(record))
	_pending_flush_events += 1
	var now := Time.get_ticks_msec()
	if (
		force_flush
		or _pending_flush_events >= FLUSH_EVENT_COUNT
		or now - _last_flush_ticks_msec >= FLUSH_INTERVAL_MSEC
	):
		_file.flush()
		_pending_flush_events = 0
		_last_flush_ticks_msec = now
