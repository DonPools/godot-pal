class_name R9FieldTestTestSuite
extends RefCounted

const TEST_INPUT_LOG := "res://tests/.tmp_r9_input_log.jsonl"

var _failures: PackedStringArray = []


func run(scene_tree: SceneTree) -> PackedStringArray:
	_test_input_logger(scene_tree)
	_test_validator()
	return _failures


func _test_input_logger(scene_tree: SceneTree) -> void:
	_remove_if_exists(TEST_INPUT_LOG)
	var logger := R9FieldTestInputLogger.new()
	scene_tree.root.add_child(logger)
	_expect(
		logger.start(TEST_INPUT_LOG) == OK,
		"R9 field-test logger should create a fresh JSONL evidence file"
	)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = true
	logger._input(key)
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.position = Vector2(320.0, 180.0)
	mouse.pressed = true
	logger._input(mouse)
	logger.stop()
	var duplicate := R9FieldTestInputLogger.new()
	scene_tree.root.add_child(duplicate)
	_expect(
		duplicate.start(TEST_INPUT_LOG) == ERR_ALREADY_EXISTS,
		"R9 field-test logger should not overwrite an existing evidence log"
	)
	duplicate.queue_free()
	logger.queue_free()
	var file := FileAccess.open(TEST_INPUT_LOG, FileAccess.READ)
	var records: Array[Dictionary] = []
	if file != null:
		while not file.eof_reached():
			var line := file.get_line().strip_edges()
			if line.is_empty():
				continue
			var parsed: Variant = JSON.parse_string(line)
			if parsed is Dictionary:
				records.append(parsed as Dictionary)
		file.close()
	_expect(
		records.size() == 4
		and records[0].get("kind") == "session_start"
		and records[1].get("type") == "key"
		and (records[1].get("actions", []) as Array).has("move_north")
		and records[2].get("type") == "mouse_button"
		and records[3].get("kind") == "session_end",
		"R9 field-test logger should preserve session metadata and chronological real input"
	)
	_remove_if_exists(TEST_INPUT_LOG)


func _test_validator() -> void:
	var template_file := FileAccess.open(
		"res://docs/baselines/r9/field-test-results.template.json",
		FileAccess.READ
	)
	_expect(template_file != null, "R9 field-test results template should be readable")
	if template_file == null:
		return
	var parsed: Variant = JSON.parse_string(template_file.get_as_text())
	template_file.close()
	_expect(parsed is Dictionary, "R9 field-test results template should contain valid JSON")
	if not parsed is Dictionary:
		return
	var validator := R9FieldTestValidator.new()
	var pending := validator.validate(parsed as Dictionary, false)
	_expect(
		not bool(pending.get("ok", true))
		and int((pending.get("recordings", {}) as Dictionary).get("found", 0)) == 4,
		"R9 field-test validator should reject an untouched pending template"
	)
	var complete := (parsed as Dictionary).duplicate(true)
	complete["date"] = "2026-08-20"
	complete["build_commit"] = "1234567890abcdef"
	complete["godot_revision"] = "4173760fdf6c2c722e82e08cb58e55f34c9efd80"
	for raw_recording: Variant in complete.get("recordings", []):
		var recording := raw_recording as Dictionary
		recording["duration_seconds"] = 90.0
		recording["reviewed"] = true
		recording["result"] = "pass"
		var checks := recording.get("checks", {}) as Dictionary
		for check_id: Variant in checks.keys():
			checks[check_id] = true
	for raw_participant: Variant in complete.get("participants", []):
		var participant := raw_participant as Dictionary
		participant["device_model"] = "test device"
		participant["first_move_seconds"] = 10.0
		participant["interaction_understood_seconds"] = 45.0
		participant["basic_attack"] = true
		participant["skill"] = true
		participant["dodge"] = true
		participant["distinguished_hp_mp"] = true
		participant["menu_settings_roundtrip"] = true
		participant["quotes"] = ["raw observation"]
	var passed := validator.validate(complete, false)
	_expect(
		bool(passed.get("ok", false))
		and int((passed.get("recordings", {}) as Dictionary).get("passed", 0)) == 4
		and int((passed.get("participants", {}) as Dictionary).get("combat_passed", 0)) == 5,
		"R9 field-test validator should accept all four reviewed recordings and five passing participants"
	)
	var failed := complete.duplicate(true)
	((failed.get("participants", []) as Array)[0] as Dictionary)["severe_failures"] = [
		"input lock"
	]
	_expect(
		not bool(validator.validate(failed, false).get("ok", true)),
		"R9 field-test validator should reject any severe first-player failure"
	)


func _remove_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
