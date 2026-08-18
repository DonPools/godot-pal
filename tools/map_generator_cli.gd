extends SceneTree

const CONTRACT_VERSION := 1

var _json_output: bool = false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var raw_arguments := OS.get_cmdline_user_args()
	_json_output = "--json" in raw_arguments
	var arguments := PackedStringArray()
	for argument: String in raw_arguments:
		if argument != "--json":
			arguments.append(argument)
	if arguments.size() < 2 or arguments[0] not in ["plan", "bake", "validate"]:
		_finish_usage("usage: map_generator_cli.gd -- <plan|bake|validate> <profile.tres> [--seed <int>] [--json]")
		return
	var command := arguments[0]
	var profile_path := arguments[1]
	var seed_override: Variant = null
	var index := 2
	while index < arguments.size():
		if arguments[index] == "--seed" and index + 1 < arguments.size():
			if not arguments[index + 1].is_valid_int():
				_finish_usage("--seed requires an integer")
				return
			seed_override = arguments[index + 1].to_int()
			index += 2
		else:
			_finish_usage("unknown argument: %s" % arguments[index])
			return
	var source_profile := load(profile_path) as MapGenerationProfile
	if source_profile == null:
		_finish(1, _document(command, profile_path, null, null, [{
			"code": "map_generation_profile_load_failed",
			"message": "could not load map generation profile: %s" % profile_path,
			"file": profile_path,
			"field": "profile",
			"id": "",
		}]))
		return
	var profile := source_profile
	if seed_override != null:
		profile = source_profile.duplicate(true) as MapGenerationProfile
		profile.seed = int(seed_override)
	profile.set_authoring_source_path(profile_path)
	var packed_target := ResourceLoader.load(
		profile.target_scene_path,
		"PackedScene",
		ResourceLoader.CACHE_MODE_IGNORE
	) as PackedScene
	var map_scene := packed_target.instantiate() if packed_target != null else null
	var plan := MapGenerator.new().generate(profile, map_scene)
	if map_scene != null:
		map_scene.free()
	if command == "plan":
		_finish(0 if plan.is_valid() else 1, _document(command, profile_path, profile, plan, plan.diagnostics))
		return
	if command == "validate":
		_finish(0 if plan.is_valid() else 1, _document(command, profile_path, profile, plan, plan.diagnostics))
		return
	if not plan.is_valid():
		_finish(1, _document(command, profile_path, profile, plan, plan.diagnostics))
		return
	var result := MapGenerationBaker.new().bake_atomic(profile, plan)
	var document := _document(command, profile_path, profile, plan, result.get("diagnostics", []))
	document["ok"] = bool(result.get("ok", false))
	_finish(0 if document["ok"] else 1, document)


func _document(
	command: String,
	profile_path: String,
	profile: MapGenerationProfile,
	plan: MapGenerationPlan,
	diagnostics_value: Variant
) -> Dictionary:
	var diagnostics: Array = diagnostics_value if diagnostics_value is Array else []
	return {
		"ok": diagnostics.is_empty(),
		"contract_version": CONTRACT_VERSION,
		"generator_version": (
			plan.generator_version
			if plan != null
			else MapGenerator.GENERATOR_VERSION
		),
		"command": command,
		"profile_path": profile_path,
		"target_scene": profile.target_scene_path if profile != null else "",
		"seed": plan.seed if plan != null else (profile.seed if profile != null else 0),
		"plan_hash": plan.plan_hash if plan != null else "",
		"metrics": plan.metrics if plan != null else {},
		"diagnostics": diagnostics,
	}


func _finish_usage(message: String) -> void:
	_finish(2, {
		"ok": false,
		"contract_version": CONTRACT_VERSION,
		"generator_version": MapGenerator.GENERATOR_VERSION,
		"command": "usage",
		"diagnostics": [{
			"code": "usage_error",
			"message": message,
			"file": "",
			"field": "arguments",
			"id": "",
		}],
	})


func _finish(code: int, document: Dictionary) -> void:
	print(JSON.stringify(document, "" if _json_output else "  ", true, true))
	quit(code)
