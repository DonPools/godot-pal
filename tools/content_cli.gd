extends SceneTree

const CONTRACT_VERSION := 2
const DATABASE_PATH := "res://content/content_database.tres"
const CONTENT_TYPES := ContentCatalog.TYPES

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
	if arguments.is_empty():
		_finish_usage("missing command")
		return
	match arguments[0]:
		"validate":
			_run_validate(arguments)
		"list":
			_run_list(arguments)
		"show":
			_run_show(arguments)
		"schema":
			_run_schema(arguments)
		"create":
			_run_create(arguments)
		"catalog":
			_run_catalog(arguments)
		"export-json":
			_run_export_json(arguments)
		"apply-json":
			_run_apply_json(arguments)
		"refs":
			_run_refs(arguments)
		"rename-id":
			_run_rename_id(arguments)
		"story-test":
			_run_story_test(arguments)
		_:
			_finish_usage("unknown command: %s" % arguments[0])


func _run_validate(arguments: PackedStringArray) -> void:
	if arguments.size() != 1:
		_finish_usage("usage: content_cli.gd -- validate [--json]")
		return
	var diagnostics := _validate_content()
	var errors := PackedStringArray()
	for diagnostic: Dictionary in diagnostics:
		errors.append(String(diagnostic.get("message", "content validation failed")))
	_finish(
		0 if diagnostics.is_empty() else 1,
		{
			"ok": diagnostics.is_empty(),
			"contract_version": CONTRACT_VERSION,
			"command": "validate",
			"error_count": diagnostics.size(),
			"errors": Array(errors),
			"diagnostics": diagnostics,
		}
	)


func _run_list(arguments: PackedStringArray) -> void:
	if arguments.size() > 2:
		_finish_usage("usage: content_cli.gd -- list [type] [--json]")
		return
	var requested_type := arguments[1] if arguments.size() == 2 else "all"
	if requested_type != "all" and requested_type not in CONTENT_TYPES:
		_finish_usage("unknown content type: %s" % requested_type)
		return
	var snapshot := _catalog_snapshot()
	var diagnostics: Array[Dictionary] = []
	diagnostics.assign(snapshot.get("diagnostics", []))
	if not diagnostics.is_empty():
		_finish_content_error("list", diagnostics)
		return
	var items: Array[Dictionary] = []
	for item: Dictionary in snapshot.get("items", []):
		if requested_type == "all" or item.get("type") == requested_type:
			items.append(item)
	items.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return "%s:%s" % [left.get("type"), left.get("id")] < "%s:%s" % [
			right.get("type"),
			right.get("id"),
		]
	)
	_finish(0, {
		"ok": true,
		"contract_version": CONTRACT_VERSION,
		"command": "list",
		"type": requested_type,
		"count": items.size(),
		"items": items,
		"diagnostics": [],
	})


func _run_show(arguments: PackedStringArray) -> void:
	if arguments.size() != 3 or arguments[1] not in CONTENT_TYPES:
		_finish_usage("usage: content_cli.gd -- show <type> <id> [--json]")
		return
	var content_type := arguments[1]
	var content_id := StringName(arguments[2])
	var catalog := _catalog()
	var diagnostics: Array[Dictionary] = catalog.diagnostics
	if not diagnostics.is_empty():
		_finish_content_error("show", diagnostics)
		return
	var item: Variant = catalog.find(content_type, content_id)
	if not item is Dictionary or item.is_empty():
		var diagnostic := _diagnostic(
			"content_not_found",
			"%s content does not exist: %s" % [content_type, content_id],
			"",
			"id",
			String(content_id)
		)
		_finish_content_error("show", [diagnostic])
		return
	_finish(0, {
		"ok": true,
		"contract_version": CONTRACT_VERSION,
		"command": "show",
		"type": content_type,
		"item": item,
		"diagnostics": [],
	})


func _run_schema(arguments: PackedStringArray) -> void:
	if arguments.size() > 2:
		_finish_usage("usage: content_cli.gd -- schema [type] [--json]")
		return
	var requested_type := arguments[1] if arguments.size() == 2 else "all"
	if requested_type != "all" and requested_type not in CONTENT_TYPES:
		_finish_usage("unknown content type: %s" % requested_type)
		return
	var schemas: Array[Dictionary] = []
	for content_type: String in CONTENT_TYPES:
		if requested_type == "all" or content_type == requested_type:
			schemas.append(ContentSchemaCatalog.schema_for(content_type))
	_finish(0, {
		"ok": true,
		"contract_version": CONTRACT_VERSION,
		"command": "schema",
		"type": requested_type,
		"schemas": schemas,
		"diagnostics": [],
	})


func _run_create(arguments: PackedStringArray) -> void:
	if arguments.size() < 4 or arguments[1] not in CONTENT_TYPES:
		_finish_usage(
			"usage: content_cli.gd -- create <type> <id> "
			+ "--path <res://...tres> [type options] [--json]"
		)
		return
	var parsed := _parse_create_arguments(arguments)
	var parse_diagnostics: Array[Dictionary] = []
	parse_diagnostics.assign(parsed.get("diagnostics", []))
	if not parse_diagnostics.is_empty():
		_finish_content_error("create", parse_diagnostics, 2)
		return
	var content_type := arguments[1]
	var content_id := StringName(arguments[2])
	var options: Dictionary = parsed.get("options", {})
	var path := String(options.get("path", ""))
	var diagnostics := _validate_create_target(content_type, content_id, path)
	if not diagnostics.is_empty():
		_finish_content_error("create", diagnostics)
		return
	var creation := ContentDefinitionFactory.create(content_type, content_id, options)
	diagnostics.append_array(creation.diagnostics)
	var resource := creation.resource
	if not diagnostics.is_empty() or resource == null:
		_finish_content_error("create", diagnostics)
		return
	var make_directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(path.get_base_dir())
	)
	if make_directory_error != OK:
		diagnostics.append(_diagnostic(
			"content_directory_create_failed",
			"content output directory could not be created: %s" % error_string(make_directory_error),
			path.get_base_dir(),
			"path",
			String(content_id)
		))
		_finish_content_error("create", diagnostics, 3)
		return
	var save_error := ResourceSaver.save(resource, path)
	if save_error != OK:
		diagnostics.append(_diagnostic(
			"content_save_failed",
			"content resource could not be saved: %s" % error_string(save_error),
			path,
			"path",
			String(content_id)
		))
		_finish_content_error("create", diagnostics, 3)
		return
	_finish(0, {
		"ok": true,
		"contract_version": CONTRACT_VERSION,
		"command": "create",
		"type": content_type,
		"id": String(content_id),
		"path": path,
		"registered": false,
		"next_step": (
			"reference the resource from a map binding or story"
			if content_type in ["dialogue", "story"]
			else "register the definition in content/content_database.tres"
		),
		"diagnostics": [],
	})


func _run_catalog(arguments: PackedStringArray) -> void:
	if arguments.size() != 1:
		_finish_usage("usage: content_cli.gd -- catalog [--json]")
		return
	var catalog := _catalog()
	if not catalog.diagnostics.is_empty():
		_finish_content_error("catalog", catalog.diagnostics)
		return
	var document := catalog.export_document()
	document.merge({"ok": true, "contract_version": CONTRACT_VERSION, "command": "catalog", "diagnostics": []})
	_finish(0, document)


func _run_export_json(arguments: PackedStringArray) -> void:
	if arguments.size() != 2:
		_finish_usage("usage: content_cli.gd -- export-json <res://...json> [--json]")
		return
	var path := arguments[1]
	if not _valid_res_path(path, "json"):
		_finish_content_error("export-json", [_diagnostic("content_path_invalid", "export path must be a normalized res:// .json path", path, "path")])
		return
	var catalog := _catalog()
	if not catalog.diagnostics.is_empty():
		_finish_content_error("export-json", catalog.diagnostics)
		return
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(path.get_base_dir())
	)
	if directory_error != OK:
		_finish_content_error("export-json", [_diagnostic(
			"content_directory_create_failed",
			"could not create export directory: %s" % error_string(directory_error),
			path.get_base_dir(),
			"path"
		)], 3)
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_finish_content_error("export-json", [_diagnostic("content_write_failed", "could not write export document", path, "path")], 3)
		return
	file.store_string(JSON.stringify(catalog.export_document(), "  "))
	file.close()
	_finish(0, {"ok": true, "contract_version": CONTRACT_VERSION, "command": "export-json", "path": path, "count": catalog.items.size(), "diagnostics": []})


func _run_apply_json(arguments: PackedStringArray) -> void:
	if arguments.size() != 2:
		_finish_usage("usage: content_cli.gd -- apply-json <res://...json> [--json]")
		return
	var path := arguments[1]
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_finish_content_error("apply-json", [_diagnostic("content_read_failed", "could not read apply document", path, "path")])
		return
	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	file.close()
	if error != OK or not json.data is Dictionary or not json.data.get("content") is Array:
		_finish_content_error("apply-json", [_diagnostic("content_json_invalid", "apply document must contain a content array", path, "content")])
		return
	var catalog := _catalog()
	var result := ContentDocumentApplier.new().apply(json.data, catalog)
	result["contract_version"] = CONTRACT_VERSION
	result["command"] = "apply-json"
	_finish(0 if result.get("ok", false) else 1, result)


func _run_refs(arguments: PackedStringArray) -> void:
	if arguments.size() != 2:
		_finish_usage("usage: content_cli.gd -- refs <content-id> [--json]")
		return
	var database := load(DATABASE_PATH) as ContentDatabase
	var catalog := _catalog()
	var refs := catalog.refs_to(StringName(arguments[1]), database)
	_finish(0, {"ok": true, "contract_version": CONTRACT_VERSION, "command": "refs", "content_id": arguments[1], "count": refs.size(), "refs": refs, "diagnostics": []})


func _run_rename_id(arguments: PackedStringArray) -> void:
	if arguments.size() != 4 or arguments[1] not in CONTENT_TYPES:
		_finish_usage("usage: content_cli.gd -- rename-id <type> <old-id> <new-id> [--json]")
		return
	var result := ContentMigration.new().rename_id(
		arguments[1], StringName(arguments[2]), StringName(arguments[3]), load(DATABASE_PATH) as ContentDatabase
	)
	result["contract_version"] = CONTRACT_VERSION
	result["command"] = "rename-id"
	result["diagnostics"] = [] if result.get("ok") else [_diagnostic(String(result.get("code")), String(result.get("message")), "", "id")]
	_finish(0 if result.get("ok") else 1, result)


func _run_story_test(arguments: PackedStringArray) -> void:
	if arguments.size() < 3 or arguments.size() > 5:
		_finish_usage("usage: content_cli.gd -- story-test <story-id> <trigger-id> [stage] [victory|escaped|defeat] [--json]")
		return
	var catalog := _catalog()
	var story := catalog.resource("story", StringName(arguments[1])) as StoryModule
	if story == null or StringName(arguments[2]) not in story.get_trigger_ids():
		_finish_content_error("story-test", [_diagnostic("story_trigger_invalid", "story or trigger does not exist", "", "trigger_id", arguments[1])])
		return
	var context := StoryTraceContext.new()
	context.stage = StringName(arguments[3]) if arguments.size() >= 4 else story.initial_stage
	if arguments.size() == 5:
		match arguments[4]:
			"victory": context.battle_outcome = BattleResult.Outcome.VICTORY
			"escaped": context.battle_outcome = BattleResult.Outcome.ESCAPED
			"defeat": context.battle_outcome = BattleResult.Outcome.DEFEAT
			_:
				_finish_usage("unknown battle outcome: %s" % arguments[4])
				return
	await story.run(StringName(arguments[2]), context)
	_finish(0, {"ok": true, "contract_version": CONTRACT_VERSION, "command": "story-test", "story_id": arguments[1], "trigger_id": arguments[2], "final_stage": String(context.stage), "source_completed": context.source_completed, "pending_map_id": String(context.pending_map_id), "pending_spawn_id": String(context.recorded_spawn_id), "trace": context.trace, "diagnostics": []})


func _validate_content() -> Array[Dictionary]:
	var diagnostics: Array[Dictionary] = []
	diagnostics.append_array(AssetLibrary.validate_assets())
	var database := load(DATABASE_PATH) as ContentDatabase
	if database == null:
		diagnostics.append(_diagnostic(
			"content_database_load_failed",
			"content database could not be loaded",
			DATABASE_PATH,
			""
		))
		return diagnostics
	diagnostics.append_array(ContentProjectValidator.validate(database, DATABASE_PATH))
	return diagnostics


func _find_content(content_type: String, content_id: StringName) -> Dictionary:
	var catalog := _catalog()
	return {"item": catalog.find(content_type, content_id), "diagnostics": catalog.diagnostics}


func _catalog() -> ContentCatalog:
	var catalog := ContentCatalog.new()
	catalog.build(load(DATABASE_PATH) as ContentDatabase)
	return catalog


func _catalog_snapshot() -> Dictionary:
	var catalog := _catalog()
	return {"items": catalog.list(), "diagnostics": catalog.diagnostics}


func _parse_create_arguments(arguments: PackedStringArray) -> Dictionary:
	var options: Dictionary[String, String] = {}
	var diagnostics: Array[Dictionary] = []
	var index := 3
	while index < arguments.size():
		var option := arguments[index]
		if not option.begins_with("--") or index + 1 >= arguments.size():
			diagnostics.append(_diagnostic(
				"cli_option_invalid",
				"create options must use --name value pairs: %s" % option,
				"",
				"arguments"
			))
			break
		var name := option.trim_prefix("--").replace("-", "_")
		if name not in [
			"path", "scene", "display_name", "default_spawn", "story",
			"block", "speaker", "text", "script", "dialogue", "initial_stage", "stages",
			"description", "icon", "category", "price", "max_stack", "can_discard", "can_sell",
			"usable_in_field", "usable_in_battle", "effect", "effect_amount",
			"max_hp", "max_mp", "attack", "mp_cost", "slot", "equipment_slots",
			"cooldown_seconds", "cast_seconds", "active_seconds", "recovery_seconds",
			"max_range", "radius", "target_rule", "presentation_scene", "sound",
			"duration_seconds", "tick_interval_seconds", "periodic_damage",
			"move_speed", "aggro_range", "attack_range", "leash_radius",
			"attack_windup_seconds", "attack_active_seconds", "attack_recovery_seconds",
			"combat_style", "is_boss", "projectile_speed", "charge_damage",
			"charge_windup_seconds", "charge_active_seconds", "charge_recovery_seconds",
			"charge_speed", "charge_cooldown_seconds", "charge_stagger_seconds",
			"charge_staggers_on_pillar",
			"cultivation_reward", "money_reward", "drop_item", "drop_quantity",
			"encounter_radius", "allows_escape", "reward_policy", "battle_music",
			"spawn_x", "spawn_y", "spawn_z",
			"item", "enemy", "instance_id",
			"realm", "realm_layer", "cultivation_points", "foundation",
			"next_realm", "max_layer", "layer_costs",
			"breakthrough_cultivation", "base_hp_bonus", "base_mp_bonus", "base_attack_bonus",
			"max_hp_bonus", "max_mp_bonus", "attack_bonus",
			"hp_bonus_per_layer", "mp_bonus_per_layer", "attack_bonus_per_layer",
		]:
			diagnostics.append(_diagnostic(
				"cli_option_unknown",
				"unknown create option: %s" % option,
				"",
				"arguments"
			))
			break
		options[name] = arguments[index + 1]
		index += 2
	return {"options": options, "diagnostics": diagnostics}


func _validate_create_target(
	content_type: String,
	content_id: StringName,
	path: String
) -> Array[Dictionary]:
	var diagnostics: Array[Dictionary] = []
	var expected_prefix := "item" if content_type == "equipment" else content_type
	if not _valid_id(String(content_id), expected_prefix):
		diagnostics.append(_diagnostic(
			"content_id_invalid",
			"content id must use the %s.* namespace: %s" % [content_type, content_id],
			path,
			"id",
			String(content_id)
		))
	if (
		not path.begins_with("res://")
		or path.get_extension().to_lower() != "tres"
		or path.contains("\\")
		or path.simplify_path() != path
	):
		diagnostics.append(_diagnostic(
			"content_path_invalid",
			"content path must be a res:// .tres path",
			path,
			"path",
			String(content_id)
		))
	elif FileAccess.file_exists(path) or ResourceLoader.exists(path):
		diagnostics.append(_diagnostic(
			"content_path_exists",
			"content resource already exists",
			path,
			"path",
			String(content_id)
		))
	var existing := _find_content(content_type, content_id)
	if existing.get("item") is Dictionary and not existing.get("item", {}).is_empty():
		diagnostics.append(_diagnostic(
			"content_id_exists",
			"content id already exists",
			String(existing.get("item", {}).get("path", "")),
			"id",
			String(content_id)
		))
	return diagnostics


func _valid_id(content_id: String, prefix: String) -> bool:
	if not content_id.begins_with(prefix + ".") or content_id != content_id.to_lower():
		return false
	for part: String in content_id.split("."):
		if part.is_empty() or not part.is_valid_identifier():
			return false
	return true


func _valid_res_path(path: String, extension: String) -> bool:
	return (
		path.begins_with("res://")
		and path.get_extension().to_lower() == extension
		and not path.contains("\\")
		and path.simplify_path() == path
	)


func _string_names(values: Array[StringName]) -> Array[String]:
	var result: Array[String] = []
	for value: StringName in values:
		result.append(String(value))
	return result


func _finish_content_error(
	command: String,
	diagnostics: Array[Dictionary],
	code: int = 1
) -> void:
	_finish(code, {
		"ok": false,
		"contract_version": CONTRACT_VERSION,
		"command": command,
		"error_count": diagnostics.size(),
		"diagnostics": diagnostics,
	})


func _finish_usage(message: String) -> void:
	var diagnostic := _diagnostic("cli_usage", message, "", "arguments")
	_finish(2, {
		"ok": false,
		"contract_version": CONTRACT_VERSION,
		"command": "",
		"error_count": 1,
		"diagnostics": [diagnostic],
	})


func _finish(code: int, payload: Dictionary) -> void:
	if _json_output:
		print(JSON.stringify(payload))
	elif bool(payload.get("ok", false)):
		if payload.get("command") == "validate":
			print("content validation passed")
		else:
			print(JSON.stringify(payload, "  "))
	else:
		for diagnostic: Dictionary in payload.get("diagnostics", []):
			printerr(String(diagnostic.get("message", "content command failed")))
	quit(code)


func _diagnostic(
	code: String,
	message: String,
	file: String,
	field: String,
	content_id: String = ""
) -> Dictionary:
	var result := {
		"code": code,
		"message": message,
		"file": file,
		"field": field,
	}
	if not content_id.is_empty():
		result["content_id"] = content_id
	return result
