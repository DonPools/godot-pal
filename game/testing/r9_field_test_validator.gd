class_name R9FieldTestValidator
extends RefCounted

const CONTRACT_VERSION := 1
const VIDEO_MINIMUM_BYTES := 1_000_000
const RECORDING_SPECS := {
	"golden_90s": {
		"video": "01_golden_90s.mp4",
		"log": "01_golden_90s.inputs.jsonl",
		"profile": "01_golden_90s",
		"checks": [
			"started_from_title", "moved", "interacted", "basic_attack",
			"skill", "dodge", "menu_settings_roundtrip",
		],
	},
	"pointer_and_direct_control": {
		"video": "02_pointer_and_direct_control.mp4",
		"log": "02_pointer_and_direct_control.inputs.jsonl",
		"profile": "02_pointer_and_direct_control",
		"checks": [
			"ground_click", "unreachable_click", "drag_retarget", "wasd_takeover",
			"enemy_chase", "cancel", "force_move", "stand_ground",
		],
	},
	"combat_feedback": {
		"video": "03_combat_feedback.mp4",
		"log": "03_combat_feedback.inputs.jsonl",
		"profile": "03_combat_feedback",
		"checks": [
			"basic_attack", "skill_one", "skill_two", "skill_three", "dodge",
			"resource_rejection", "cooldown_rejection", "player_hit", "victory",
			"defeat", "reduced_flashes",
		],
	},
	"device_modal_roundtrip": {
		"video": "04_device_modal_roundtrip.mp4",
		"log": "04_device_modal_roundtrip.inputs.jsonl",
		"profile": "04_device_modal_roundtrip",
		"checks": [
			"keyboard_mouse", "gamepad", "escape_menu", "secondary_menu",
			"gamepad_start", "successful_rebind", "conflict_rejected",
			"defaults_restored", "dialogue", "save_load", "returned_to_map",
		],
	},
}


func validate(document: Dictionary, check_files: bool = true) -> Dictionary:
	var diagnostics: Array[Dictionary] = []
	_validate_metadata(document, diagnostics)
	var recording_summary := _validate_recordings(document, diagnostics, check_files)
	var participant_summary := _validate_participants(document, diagnostics)
	return {
		"ok": diagnostics.is_empty(),
		"contract_version": CONTRACT_VERSION,
		"diagnostics": diagnostics,
		"recordings": recording_summary,
		"participants": participant_summary,
	}


func _validate_metadata(document: Dictionary, diagnostics: Array[Dictionary]) -> void:
	if int(document.get("schema_version", 0)) != CONTRACT_VERSION:
		_add(diagnostics, "schema_version", "schema_version", "expected schema version 1")
	for field: String in ["date", "build_commit", "godot_revision", "platform"]:
		if String(document.get(field, "")).strip_edges().is_empty():
			_add(diagnostics, "missing_metadata", field, "required metadata is empty")
	if not String(document.get("build_commit", "")).is_empty() and String(
		document.get("build_commit", "")
	).length() < 7:
		_add(diagnostics, "build_commit", "build_commit", "build commit is too short")
	if not String(document.get("godot_revision", "")).is_empty() and String(
		document.get("godot_revision", "")
	).length() < 7:
		_add(diagnostics, "godot_revision", "godot_revision", "Godot revision is too short")


func _validate_recordings(
	document: Dictionary,
	diagnostics: Array[Dictionary],
	check_files: bool
) -> Dictionary:
	var raw_recordings: Variant = document.get("recordings", [])
	if not raw_recordings is Array:
		_add(diagnostics, "recordings_type", "recordings", "recordings must be an array")
		return {"required": RECORDING_SPECS.size(), "found": 0, "passed": 0}
	var by_id: Dictionary = {}
	for raw_recording: Variant in raw_recordings as Array:
		if not raw_recording is Dictionary:
			_add(diagnostics, "recording_type", "recordings", "recording must be an object")
			continue
		var recording := raw_recording as Dictionary
		var recording_id := String(recording.get("id", ""))
		if not RECORDING_SPECS.has(recording_id):
			_add(
				diagnostics,
				"recording_id",
				"recordings.%s" % recording_id,
				"unknown recording id"
			)
			continue
		if by_id.has(recording_id):
			_add(
				diagnostics,
				"recording_duplicate",
				"recordings.%s" % recording_id,
				"recording id appears more than once"
			)
			continue
		by_id[recording_id] = recording
	var passed := 0
	for recording_id: String in RECORDING_SPECS:
		if not by_id.has(recording_id):
			_add(
				diagnostics,
				"recording_missing",
				"recordings.%s" % recording_id,
				"required recording is missing"
			)
			continue
		var before := diagnostics.size()
		_validate_recording(
			recording_id,
			by_id[recording_id] as Dictionary,
			document,
			diagnostics,
			check_files
		)
		if diagnostics.size() == before:
			passed += 1
	return {"required": RECORDING_SPECS.size(), "found": by_id.size(), "passed": passed}


func _validate_recording(
	recording_id: String,
	recording: Dictionary,
	document: Dictionary,
	diagnostics: Array[Dictionary],
	check_files: bool
) -> void:
	var field := "recordings.%s" % recording_id
	var spec := RECORDING_SPECS[recording_id] as Dictionary
	var video_path := String(recording.get("video_path", ""))
	var log_path := String(recording.get("input_log_path", ""))
	var profile_path := String(recording.get("profile_path", ""))
	if video_path.get_file() != String(spec.get("video", "")):
		_add(diagnostics, "video_name", "%s.video_path" % field, "unexpected video filename")
	if log_path.get_file() != String(spec.get("log", "")):
		_add(diagnostics, "log_name", "%s.input_log_path" % field, "unexpected input log filename")
	if profile_path.get_file() != String(spec.get("profile", "")):
		_add(diagnostics, "profile_name", "%s.profile_path" % field, "unexpected isolated profile path")
	if int(recording.get("fps", 0)) != 60:
		_add(diagnostics, "video_fps", "%s.fps" % field, "recording must be 60 FPS")
	if not _pair_matches(recording.get("resolution", []), 1280, 720):
		_add(
			diagnostics,
			"video_resolution",
			"%s.resolution" % field,
			"recording must be 1280 x 720"
		)
	if float(recording.get("duration_seconds", 0.0)) <= 0.0:
		_add(diagnostics, "video_duration", "%s.duration_seconds" % field, "duration is missing")
	if not bool(recording.get("reviewed", false)):
		_add(diagnostics, "video_review", "%s.reviewed" % field, "frame review is incomplete")
	if String(recording.get("result", "")) != "pass":
		_add(diagnostics, "recording_result", "%s.result" % field, "recording did not pass")
	var checks: Variant = recording.get("checks", {})
	if not checks is Dictionary:
		_add(diagnostics, "recording_checks", "%s.checks" % field, "checks must be an object")
	else:
		for required_check: String in spec.get("checks", []):
			if not bool((checks as Dictionary).get(required_check, false)):
				_add(
					diagnostics,
					"recording_coverage",
					"%s.checks.%s" % [field, required_check],
					"required coverage is not confirmed"
				)
	if not check_files:
		return
	_validate_video_file(video_path, "%s.video_path" % field, diagnostics)
	_validate_input_log(
		log_path,
		field,
		String(document.get("godot_revision", "")),
		recording_id,
		profile_path,
		diagnostics
	)


func _validate_video_file(
	path: String,
	field: String,
	diagnostics: Array[Dictionary]
) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_add(diagnostics, "video_missing", field, "video file cannot be read")
		return
	var length := file.get_length()
	file.close()
	if length < VIDEO_MINIMUM_BYTES:
		_add(diagnostics, "video_too_small", field, "video file is too small to be evidence")


func _validate_input_log(
	path: String,
	field: String,
	expected_revision: String,
	recording_id: String,
	expected_profile: String,
	diagnostics: Array[Dictionary]
) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_add(diagnostics, "input_log_missing", "%s.input_log_path" % field, "input log cannot be read")
		return
	var start: Dictionary = {}
	var saw_end := false
	var input_count := 0
	var input_types: Dictionary = {}
	var line_number := 0
	while not file.eof_reached():
		line_number += 1
		var line := file.get_line().strip_edges()
		if line.is_empty():
			continue
		var parsed: Variant = JSON.parse_string(line)
		if not parsed is Dictionary:
			_add(
				diagnostics,
				"input_log_json",
				"%s.input_log_path:%d" % [field, line_number],
				"input log line is not a JSON object"
			)
			continue
		var record := parsed as Dictionary
		match String(record.get("kind", "")):
			"session_start":
				if start.is_empty():
					start = record
			"session_end":
				saw_end = true
			"input":
				input_count += 1
				input_types[String(record.get("type", ""))] = true
	file.close()
	if start.is_empty():
		_add(diagnostics, "input_log_start", "%s.input_log_path" % field, "session_start is missing")
	else:
		if String(start.get("display_driver", "")) == "headless":
			_add(diagnostics, "input_log_headless", "%s.input_log_path" % field, "real input cannot use headless mode")
		if String(start.get("rendering_method", "")) != "gl_compatibility":
			_add(diagnostics, "input_log_renderer", "%s.input_log_path" % field, "Compatibility renderer is required")
		if not _pair_matches(start.get("viewport", []), 640, 360):
			_add(diagnostics, "input_log_viewport", "%s.input_log_path" % field, "viewport must be 640 x 360")
		if not _pair_matches(start.get("window", []), 1280, 720):
			_add(diagnostics, "input_log_window", "%s.input_log_path" % field, "window must be 1280 x 720")
		var engine := start.get("engine", {}) as Dictionary
		if not expected_revision.is_empty() and String(engine.get("hash", "")) != expected_revision:
			_add(diagnostics, "input_log_revision", "%s.input_log_path" % field, "Godot revision does not match")
		if expected_profile.is_empty() or String(start.get("field_test_profile", "")) != expected_profile:
			_add(diagnostics, "input_log_profile", "%s.input_log_path" % field, "isolated profile does not match")
	if not saw_end:
		_add(diagnostics, "input_log_end", "%s.input_log_path" % field, "session_end is missing")
	if input_count == 0:
		_add(diagnostics, "input_log_empty", "%s.input_log_path" % field, "no real input was recorded")
	if recording_id == "device_modal_roundtrip":
		var keyboard_mouse := input_types.has("key") or input_types.has("mouse_button")
		var gamepad := input_types.has("joy_button") or input_types.has("joy_motion")
		if not keyboard_mouse or not gamepad:
			_add(diagnostics, "input_log_devices", "%s.input_log_path" % field, "modal run must contain keyboard/mouse and gamepad input")


func _validate_participants(
	document: Dictionary,
	diagnostics: Array[Dictionary]
) -> Dictionary:
	var raw_participants: Variant = document.get("participants", [])
	if not raw_participants is Array:
		_add(diagnostics, "participants_type", "participants", "participants must be an array")
		return {"required": 5, "found": 0}
	var participants := raw_participants as Array
	if participants.size() != 5:
		_add(diagnostics, "participant_count", "participants", "exactly five participants are required")
	var ids: Dictionary = {}
	var keyboard_mouse_count := 0
	var gamepad_count := 0
	var first_move_success := 0
	var interaction_success := 0
	var combat_success := 0
	var menu_success := 0
	var severe_failure_count := 0
	for index: int in range(participants.size()):
		var raw: Variant = participants[index]
		if not raw is Dictionary:
			_add(diagnostics, "participant_type", "participants.%d" % index, "participant must be an object")
			continue
		var participant := raw as Dictionary
		var participant_id := String(participant.get("id", ""))
		var field := "participants.%s" % participant_id
		if participant_id.is_empty() or ids.has(participant_id):
			_add(diagnostics, "participant_id", field, "participant id is empty or duplicated")
		else:
			ids[participant_id] = true
		var device := String(participant.get("device", ""))
		if device == "keyboard_mouse":
			keyboard_mouse_count += 1
		elif device == "gamepad":
			gamepad_count += 1
		else:
			_add(diagnostics, "participant_device", "%s.device" % field, "unknown input device")
		if String(participant.get("device_model", "")).strip_edges().is_empty():
			_add(diagnostics, "participant_device_model", "%s.device_model" % field, "device model is missing")
		var first_move := float(participant.get("first_move_seconds", -1.0))
		var interaction := float(participant.get("interaction_understood_seconds", -1.0))
		if first_move >= 0.0 and first_move <= 30.0:
			first_move_success += 1
		if interaction >= 0.0 and interaction <= 90.0:
			interaction_success += 1
		if (
			bool(participant.get("basic_attack", false))
			and bool(participant.get("skill", false))
			and bool(participant.get("dodge", false))
			and bool(participant.get("distinguished_hp_mp", false))
		):
			combat_success += 1
		if bool(participant.get("menu_settings_roundtrip", false)):
			menu_success += 1
		var severe: Variant = participant.get("severe_failures", [])
		if not severe is Array:
			_add(diagnostics, "participant_failures", "%s.severe_failures" % field, "severe_failures must be an array")
		else:
			severe_failure_count += (severe as Array).size()
		var quotes: Variant = participant.get("quotes", [])
		if not quotes is Array or (quotes as Array).is_empty():
			_add(diagnostics, "participant_quotes", "%s.quotes" % field, "at least one raw observation or quote is required")
	for required_id: String in ["P1", "P2", "P3", "P4", "P5"]:
		if not ids.has(required_id):
			_add(diagnostics, "participant_id", "participants.%s" % required_id, "required anonymous participant id is missing")
	if keyboard_mouse_count < 2 or gamepad_count < 2:
		_add(diagnostics, "participant_device_coverage", "participants", "keyboard/mouse and gamepad each need at least two participants")
	for result: Dictionary in [
		{"field": "first_move", "count": first_move_success},
		{"field": "interaction", "count": interaction_success},
		{"field": "combat", "count": combat_success},
		{"field": "menu", "count": menu_success},
	]:
		if int(result.get("count", 0)) < 4:
			_add(diagnostics, "participant_threshold", "participants.%s" % result.get("field"), "fewer than four participants passed")
	if severe_failure_count > 0:
		_add(diagnostics, "participant_severe_failure", "participants.severe_failures", "all five runs must be free of severe failures")
	return {
		"required": 5,
		"found": participants.size(),
		"keyboard_mouse": keyboard_mouse_count,
		"gamepad": gamepad_count,
		"first_move_passed": first_move_success,
		"interaction_passed": interaction_success,
		"combat_passed": combat_success,
		"menu_passed": menu_success,
		"severe_failures": severe_failure_count,
	}


func _pair_matches(value: Variant, expected_x: int, expected_y: int) -> bool:
	return (
		value is Array
		and (value as Array).size() == 2
		and int((value as Array)[0]) == expected_x
		and int((value as Array)[1]) == expected_y
	)


func _add(
	diagnostics: Array[Dictionary],
	code: String,
	field: String,
	message: String
) -> void:
	diagnostics.append({"code": code, "field": field, "message": message})
