extends SceneTree

const CONTRACT_VERSION := 1
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
			schemas.append(_schema_for(content_type))
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
	var resource: Resource
	match content_type:
		"map":
			var created_map := _create_map(content_id, options, diagnostics)
			resource = created_map
		"dialogue":
			resource = _create_dialogue(content_id, options)
		"story":
			resource = _create_story(content_id, options, diagnostics)
		_:
			resource = _create_definition(content_type, content_id, options, diagnostics)
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
	for message: String in database.build_index():
		diagnostics.append(_diagnostic(
			"content_database_invalid",
			message,
			DATABASE_PATH,
			"maps"
		))
	var scanned := ContentSourceScanner.new().scan_story_resources()
	diagnostics.append_array(scanned.get("diagnostics", []))
	var stories: Array[StoryModule] = []
	stories.assign(scanned.get("stories", []))
	var dialogues: Array[DialogueDefinition] = []
	dialogues.assign(scanned.get("dialogues", []))
	_validate_stories(stories, diagnostics)
	for story: StoryModule in stories:
		if story.dialogue != null and story.dialogue not in dialogues:
			dialogues.append(story.dialogue)
	_validate_dialogues(dialogues, diagnostics)
	for message: String in MapSceneValidator.new().validate(database, stories):
		diagnostics.append(_diagnostic(
			"map_scene_invalid",
			message,
			_map_file_for_message(database, message),
			"scene"
		))
	_validate_embedded_bindings(database, diagnostics)
	return diagnostics


func _validate_stories(
	stories: Array[StoryModule],
	diagnostics: Array[Dictionary]
) -> void:
	var ids: Dictionary[StringName, String] = {}
	for story: StoryModule in stories:
		var path := story.resource_path
		if story.id.is_empty() or not _valid_id(String(story.id), "story"):
			diagnostics.append(_diagnostic(
				"story_id_invalid",
				"StoryModule id must use the story.* namespace: %s" % story.id,
				path,
				"id",
				String(story.id)
			))
		elif ids.has(story.id):
			diagnostics.append(_diagnostic(
				"story_id_duplicate",
				"StoryModule id is repeated; first declared in %s" % ids[story.id],
				path,
				"id",
				String(story.id)
			))
		else:
			ids[story.id] = path
		var stages: Dictionary[StringName, bool] = {}
		for stage_id: StringName in story.valid_stages:
			if stage_id.is_empty() or stages.has(stage_id):
				diagnostics.append(_diagnostic(
					"story_stage_invalid",
					"StoryModule contains an empty or repeated stage: %s" % stage_id,
					path,
					"valid_stages",
					String(story.id)
				))
			stages[stage_id] = true
		if story.initial_stage.is_empty() or not stages.has(story.initial_stage):
			diagnostics.append(_diagnostic(
				"story_initial_stage_invalid",
				"StoryModule initial_stage is not listed in valid_stages: %s" % story.initial_stage,
				path,
				"initial_stage",
				String(story.id)
			))
		var triggers: Dictionary[StringName, bool] = {}
		for trigger_id: StringName in story.get_trigger_ids():
			if trigger_id.is_empty() or triggers.has(trigger_id):
				diagnostics.append(_diagnostic(
					"story_trigger_invalid",
					"StoryModule contains an empty or repeated trigger: %s" % trigger_id,
					path,
					"get_trigger_ids",
					String(story.id)
				))
			triggers[trigger_id] = true


func _validate_dialogues(
	dialogues: Array[DialogueDefinition],
	diagnostics: Array[Dictionary]
) -> void:
	var ids: Dictionary[StringName, String] = {}
	var seen_paths: Dictionary[String, bool] = {}
	for dialogue: DialogueDefinition in dialogues:
		var path := dialogue.resource_path
		if not path.is_empty() and seen_paths.has(path):
			continue
		seen_paths[path] = true
		if dialogue.id.is_empty() or not _valid_id(String(dialogue.id), "dialogue"):
			diagnostics.append(_diagnostic(
				"dialogue_id_invalid",
				"DialogueDefinition id must use the dialogue.* namespace: %s" % dialogue.id,
				path,
				"id",
				String(dialogue.id)
			))
		elif ids.has(dialogue.id):
			diagnostics.append(_diagnostic(
				"dialogue_id_duplicate",
				"DialogueDefinition id is repeated; first declared in %s" % ids[dialogue.id],
				path,
				"id",
				String(dialogue.id)
			))
		else:
			ids[dialogue.id] = path
		for message: String in dialogue.validate():
			diagnostics.append(_diagnostic(
				"dialogue_invalid",
				message,
				path,
				"blocks",
				String(dialogue.id)
			))


func _validate_embedded_bindings(
	database: ContentDatabase,
	diagnostics: Array[Dictionary]
) -> void:
	for record: Dictionary in ContentSourceScanner.new().scan_embedded_bindings(database):
		var binding := record.get("binding") as StoryBinding
		var file := String(record.get("file", ""))
		var field := "%s:%s" % [record.get("node_path"), record.get("field")]
		if binding == null or binding.event == null:
			diagnostics.append(_diagnostic(
				"story_binding_event_missing",
				"StoryBinding has no event",
				file,
				field,
				String(record.get("map_id", ""))
			))
		elif binding.trigger_id.is_empty() or binding.trigger_id not in binding.event.get_trigger_ids():
			diagnostics.append(_diagnostic(
				"story_binding_trigger_invalid",
				"StoryBinding references an unknown trigger: %s" % binding.trigger_id,
				file,
				field,
				String(record.get("map_id", ""))
			))


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


func _schema_for(content_type: String) -> Dictionary:
	match content_type:
		"actor":
			return _definition_schema("actor", "ActorDefinition", [
				_field("base_max_hp", "int", false, 100),
				_field("base_max_mp", "int", false, 20),
				_field("initial_level", "int", false, 1),
			])
		"item":
			return _definition_schema("item", "ItemDefinition", [
				_field("price", "int", false, 0),
				_field("max_stack", "int", false, 9),
				_field("effects", "Array[GameEffect]", false, []),
			])
		"equipment":
			return _definition_schema("equipment", "EquipmentDefinition", [
				_field("slot", "StringName", true, "weapon"),
				_field("price", "int", false, 0),
			])
		"skill":
			return _definition_schema("skill", "SkillDefinition", [
				_field("mp_cost", "int", false, 0),
				_field("effects", "Array[GameEffect]", false, []),
			])
		"status":
			return _definition_schema("status", "StatusDefinition", [
				_field("duration_rounds", "int", false, 1),
				_field("periodic_damage", "int", false, 0),
			])
		"enemy":
			return _definition_schema("enemy", "EnemyDefinition", [
				_field("max_hp", "int", false, 30),
				_field("attack", "int", false, 8),
				_field("strategy", "EnemyStrategy", true, null),
			])
		"shop":
			var schema := _definition_schema("shop", "ShopDefinition", [
				_field("entries", "Array[ShopEntry]", true, []),
			])
			schema["create_required_options"] = ["path", "item"]
			return schema
		"encounter":
			var schema := _definition_schema("encounter", "BattleEncounter", [
				_field("enemies", "Array[EncounterEnemy]", true, []),
				_field("allows_escape", "bool", false, true),
			])
			schema["create_required_options"] = ["path", "enemy"]
			return schema
		"map":
			return {
				"type": "map",
				"resource_class": "MapDefinition",
				"id_prefix": "map.",
				"create_required_options": ["path", "scene"],
				"fields": [
					_field("id", "StringName", true, ""),
					_field("display_name", "String", true, ""),
					_field("description", "String", false, ""),
					_field("tags", "Array[StringName]", false, []),
					_field("scene", "PackedScene", true, null),
					_field("default_spawn_id", "StringName", true, "default"),
					_field("music", "AudioStream", false, null),
				],
			}
		"dialogue":
			return {
				"type": "dialogue",
				"resource_class": "DialogueDefinition",
				"id_prefix": "dialogue.",
				"create_required_options": ["path"],
				"fields": [
					_field("id", "StringName", true, ""),
					_field("blocks", "Array[DialogueBlock]", true, []),
				],
			}
		"story":
			return {
				"type": "story",
				"resource_class": "StoryModule",
				"id_prefix": "story.",
				"create_required_options": ["path"],
				"fields": [
					_field("id", "StringName", true, ""),
					_field("initial_stage", "StringName", true, "not_started"),
					_field("valid_stages", "Array[StringName]", true, ["not_started"]),
					_field("dialogue", "DialogueDefinition", false, null),
				],
			}
	return {}


func _definition_schema(
	content_type: String,
	resource_class: String,
	additional_fields: Array[Dictionary]
) -> Dictionary:
	var fields: Array[Dictionary] = [
		_field("id", "StringName", true, ""),
		_field("display_name", "String", true, ""),
		_field("description", "String", false, ""),
		_field("tags", "Array[StringName]", false, []),
	]
	fields.append_array(additional_fields)
	return {
		"type": content_type,
		"resource_class": resource_class,
		"id_prefix": "item." if content_type == "equipment" else content_type + ".",
		"create_required_options": ["path"],
		"fields": fields,
	}


func _field(name: String, type: String, required: bool, default_value: Variant) -> Dictionary:
	return {
		"name": name,
		"type": type,
		"required": required,
		"default": default_value,
	}


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
			"path", "scene", "display_name", "default_spawn",
			"block", "speaker", "text", "script", "dialogue", "initial_stage", "stages",
			"description", "price", "max_stack", "max_hp", "max_mp", "attack", "mp_cost", "slot",
			"duration_rounds", "periodic_damage",
			"item", "enemy", "instance_id",
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


func _create_definition(
	content_type: String,
	content_id: StringName,
	options: Dictionary,
	diagnostics: Array[Dictionary]
) -> Resource:
	var definition: ContentDefinition
	match content_type:
		"actor": definition = ActorDefinition.new()
		"item": definition = ItemDefinition.new()
		"equipment": definition = EquipmentDefinition.new()
		"skill": definition = SkillDefinition.new()
		"status": definition = StatusDefinition.new()
		"enemy": definition = EnemyDefinition.new()
		"shop": definition = ShopDefinition.new()
		"encounter": definition = BattleEncounter.new()
		_:
			diagnostics.append(_diagnostic("content_type_unsupported", "create does not support %s" % content_type, "", "type"))
			return null
	definition.id = content_id
	definition.display_name = String(options.get("display_name", String(content_id).get_slice(".", String(content_id).get_slice_count(".") - 1)))
	definition.description = String(options.get("description", "TODO"))
	if definition is ActorDefinition:
		var actor := definition as ActorDefinition
		actor.base_max_hp = int(options.get("max_hp", "100"))
		actor.base_max_mp = int(options.get("max_mp", "20"))
	elif definition is EquipmentDefinition:
		var equipment := definition as EquipmentDefinition
		equipment.price = int(options.get("price", "0"))
		equipment.slot = StringName(options.get("slot", "weapon"))
	elif definition is ItemDefinition:
		var item := definition as ItemDefinition
		item.price = int(options.get("price", "0"))
		item.max_stack = int(options.get("max_stack", "9"))
	elif definition is SkillDefinition:
		(definition as SkillDefinition).mp_cost = int(options.get("mp_cost", "0"))
	elif definition is StatusDefinition:
		var status := definition as StatusDefinition
		status.duration_rounds = int(options.get("duration_rounds", "1"))
		status.periodic_damage = int(options.get("periodic_damage", "0"))
	elif definition is EnemyDefinition:
		var enemy := definition as EnemyDefinition
		enemy.max_hp = int(options.get("max_hp", "30"))
		enemy.attack = int(options.get("attack", "8"))
		enemy.strategy = BasicAttackStrategy.new()
	elif definition is ShopDefinition:
		var shop_item := load(String(options.get("item", ""))) as ItemDefinition
		if shop_item == null:
			diagnostics.append(_diagnostic(
				"shop_item_load_failed",
				"shop create requires --item with an ItemDefinition path",
				String(options.get("item", "")),
				"entries",
				String(content_id)
			))
			return null
		var entry := ShopEntry.new()
		entry.item = shop_item
		(definition as ShopDefinition).entries.assign([entry])
	elif definition is BattleEncounter:
		var enemy_definition := load(String(options.get("enemy", ""))) as EnemyDefinition
		if enemy_definition == null:
			diagnostics.append(_diagnostic(
				"encounter_enemy_load_failed",
				"encounter create requires --enemy with an EnemyDefinition path",
				String(options.get("enemy", "")),
				"enemies",
				String(content_id)
			))
			return null
		var encounter_enemy := EncounterEnemy.new()
		encounter_enemy.enemy = enemy_definition
		encounter_enemy.instance_id = StringName(options.get("instance_id", "enemy"))
		(definition as BattleEncounter).enemies.assign([encounter_enemy])
	return definition


func _create_map(
	content_id: StringName,
	options: Dictionary,
	diagnostics: Array[Dictionary]
) -> MapDefinition:
	var scene_path := String(options.get("scene", ""))
	var scene := load(scene_path) as PackedScene
	if scene == null:
		diagnostics.append(_diagnostic(
			"map_scene_load_failed",
			"map create requires a valid --scene PackedScene",
			scene_path,
			"scene",
			String(content_id)
		))
		return null
	var instance := scene.instantiate()
	if not instance is MapGameScene:
		diagnostics.append(_diagnostic(
			"map_scene_type_invalid",
			"map scene root must inherit MapGameScene",
			scene_path,
			"scene",
			String(content_id)
		))
		instance.free()
		return null
	var default_spawn := StringName(options.get("default_spawn", "start"))
	if instance.get_node_or_null(^"SpawnPoints") == null or (
		instance.get_node(^"SpawnPoints").get_node_or_null(NodePath(String(default_spawn))) == null
	):
		diagnostics.append(_diagnostic(
			"map_default_spawn_invalid",
			"map scene does not contain default spawn: %s" % default_spawn,
			scene_path,
			"default_spawn_id",
			String(content_id)
		))
		instance.free()
		return null
	instance.free()
	var definition := MapDefinition.new()
	definition.id = content_id
	definition.display_name = String(options.get("display_name", String(content_id).get_slice(".", String(content_id).get_slice_count(".") - 1)))
	definition.scene = scene
	definition.default_spawn_id = default_spawn
	return definition


func _create_dialogue(content_id: StringName, options: Dictionary) -> DialogueDefinition:
	var entry := DialogueEntry.new()
	entry.speaker = String(options.get("speaker", ""))
	entry.text = String(options.get("text", "TODO"))
	var block := DialogueBlock.new()
	block.id = StringName(options.get("block", "default"))
	block.entries.assign([entry])
	var dialogue := DialogueDefinition.new()
	dialogue.id = content_id
	dialogue.blocks.assign([block])
	return dialogue


func _create_story(
	content_id: StringName,
	options: Dictionary,
	diagnostics: Array[Dictionary]
) -> StoryModule:
	var story: StoryModule
	var script_path := String(options.get("script", ""))
	if script_path.is_empty():
		story = StoryModule.new()
	else:
		var script := load(script_path) as Script
		if script == null or not script.can_instantiate():
			diagnostics.append(_diagnostic(
				"story_script_load_failed",
				"story --script must be an instantiable GDScript",
				script_path,
				"script",
				String(content_id)
			))
			return null
		story = script.new() as StoryModule
		if story == null:
			diagnostics.append(_diagnostic(
				"story_script_type_invalid",
				"story --script must extend StoryModule",
				script_path,
				"script",
				String(content_id)
			))
			return null
	story.id = content_id
	story.initial_stage = StringName(options.get("initial_stage", "not_started"))
	var stages := PackedStringArray(String(options.get("stages", "not_started")).split(",", false))
	for stage: String in stages:
		story.valid_stages.append(StringName(stage.strip_edges()))
	if story.initial_stage not in story.valid_stages:
		diagnostics.append(_diagnostic(
			"story_initial_stage_invalid",
			"story initial stage must appear in --stages",
			String(options.get("path", "")),
			"initial_stage",
			String(content_id)
		))
		return null
	var dialogue_path := String(options.get("dialogue", ""))
	if not dialogue_path.is_empty():
		story.dialogue = load(dialogue_path) as DialogueDefinition
		if story.dialogue == null:
			diagnostics.append(_diagnostic(
				"story_dialogue_load_failed",
				"story --dialogue must reference a DialogueDefinition",
				dialogue_path,
				"dialogue",
				String(content_id)
			))
			return null
	return story


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


func _map_file_for_message(database: ContentDatabase, message: String) -> String:
	for definition: MapDefinition in database.maps:
		if definition != null and message.begins_with("map %s " % definition.id):
			return definition.scene.resource_path if definition.scene != null else definition.resource_path
	return DATABASE_PATH


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
