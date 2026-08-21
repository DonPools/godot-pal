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
	var scanned := ContentSourceScanner.new().scan_story_resources(database.story_directories)
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
		"realm":
			return _definition_schema("realm", "CultivationRealmDefinition", [
				_field("max_layer", "int", false, 1),
				_field("layer_cultivation_costs", "PackedInt32Array", false, []),
				_field("breakthrough_cultivation_required", "int", false, 0),
				_field("next_realm", "CultivationRealmDefinition", false, null),
				_field("base_max_hp_bonus", "int", false, 0),
				_field("base_max_mp_bonus", "int", false, 0),
				_field("base_attack_bonus", "int", false, 0),
				_field("max_hp_bonus_per_layer", "int", false, 0),
				_field("max_mp_bonus_per_layer", "int", false, 0),
				_field("attack_bonus_per_layer", "int", false, 0),
			])
		"foundation":
			var schema := _definition_schema("foundation", "DaoFoundationDefinition", [
				_field("required_realm", "CultivationRealmDefinition", true, null),
				_field("granted_skills", "Array[SkillDefinition]", false, []),
				_field("battle_modifier", "BattleBuildModifier", false, null),
				_field("aura_color", "Color", false, "8ccccfff"),
				_field("max_hp_bonus", "int", false, 0),
				_field("max_mp_bonus", "int", false, 0),
				_field("attack_bonus", "int", false, 0),
			])
			schema["create_required_options"] = ["path", "realm"]
			return schema
		"actor":
			var schema := _definition_schema("actor", "ActorDefinition", [
				_field("base_max_hp", "int", false, 100),
				_field("base_max_mp", "int", false, 20),
				_field("base_attack", "int", false, 12),
				_field("initial_realm", "CultivationRealmDefinition", true, null),
				_field("initial_realm_layer", "int", false, 1),
				_field("initial_cultivation_points", "int", false, 0),
				_field("initial_foundation", "DaoFoundationDefinition", false, null),
				_field("equipment_slots", "Array[StringName]", false, ["weapon"]),
			])
			schema["create_required_options"] = ["path", "realm"]
			return schema
		"npc":
			var schema := _definition_schema("npc", "NpcDefinition", [
				_field("field_model_3d", "PackedScene", true, null),
			])
			schema["create_required_options"] = ["path", "scene"]
			return schema
		"item":
			return _definition_schema("item", "ItemDefinition", [
				_field("icon", "Texture2D", false, null),
				_field("price", "int", false, 0),
				_field("max_stack", "int", false, 9),
				_field("can_discard", "bool", false, true),
				_field("can_sell", "bool", false, true),
				_field("effects", "Array[GameEffect]", false, []),
			])
		"equipment":
			return _definition_schema("equipment", "EquipmentDefinition", [
				_field("icon", "Texture2D", false, null),
				_field("slot", "StringName", true, "weapon"),
				_field("price", "int", false, 0),
				_field("can_discard", "bool", false, true),
				_field("can_sell", "bool", false, true),
			])
		"skill":
			return _definition_schema("skill", "SkillDefinition", [
				_field("icon", "Texture2D", false, null),
				_field("mp_cost", "int", false, 0),
				_field("target_rule", "SkillDefinition.TargetRule", false, "direction"),
				_field("cooldown_seconds", "float", false, 0.0),
				_field("cast_seconds", "float", false, 0.0),
				_field("active_seconds", "float", false, 0.1),
				_field("recovery_seconds", "float", false, 0.2),
				_field("max_range", "float", false, 1.5),
				_field("radius", "float", false, 0.0),
				_field("effects", "Array[GameEffect]", false, []),
				_field("presentation_scene", "PackedScene", false, null),
				_field("sound", "AudioStream", false, null),
			])
		"status":
			return _definition_schema("status", "StatusDefinition", [
				_field("duration_seconds", "float", false, 1.0),
				_field("tick_interval_seconds", "float", false, 1.0),
				_field("periodic_damage", "int", false, 0),
			])
		"enemy":
			var schema := _definition_schema("enemy", "EnemyDefinition", [
				_field("max_hp", "int", false, 30),
				_field("attack", "int", false, 8),
				_field("cultivation_reward", "int", false, 0),
				_field("character_scene", "PackedScene", true, null),
				_field("move_speed", "float", false, 3.0),
				_field("aggro_range", "float", false, 8.0),
				_field("attack_range", "float", false, 1.5),
				_field("leash_radius", "float", false, 12.0),
				_field("attack_windup_seconds", "float", false, 0.35),
				_field("attack_active_seconds", "float", false, 0.1),
				_field("attack_recovery_seconds", "float", false, 0.45),
				_field("money_reward", "int", false, 0),
				_field("drop_item", "ItemDefinition", false, null),
				_field("drop_quantity", "int", false, 0),
				_field("strategy", "EnemyStrategy", true, null),
			])
			schema["create_required_options"] = ["path", "scene"]
			return schema
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
				_field("encounter_radius", "float", false, 10.0),
				_field("leash_radius", "float", false, 14.0),
				_field("reward_policy", "RewardPolicy.Value", false, "all_or_nothing"),
				_field("battle_music", "AudioStream", false, null),
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
					_field("story_module", "StoryModule", false, null),
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
			"path", "scene", "display_name", "default_spawn", "story",
			"block", "speaker", "text", "script", "dialogue", "initial_stage", "stages",
			"description", "icon", "price", "max_stack", "can_discard", "can_sell",
			"max_hp", "max_mp", "attack", "mp_cost", "slot", "equipment_slots",
			"cooldown_seconds", "cast_seconds", "active_seconds", "recovery_seconds",
			"max_range", "radius", "target_rule", "presentation_scene", "sound",
			"duration_seconds", "tick_interval_seconds", "periodic_damage",
			"move_speed", "aggro_range", "attack_range", "leash_radius",
			"attack_windup_seconds", "attack_active_seconds", "attack_recovery_seconds",
			"cultivation_reward", "money_reward", "drop_item", "drop_quantity",
			"encounter_radius", "allows_escape", "reward_policy", "battle_music",
			"spawn_x", "spawn_y", "spawn_z", "level_modifier",
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


func _create_definition(
	content_type: String,
	content_id: StringName,
	options: Dictionary,
	diagnostics: Array[Dictionary]
) -> Resource:
	var definition: ContentDefinition
	match content_type:
		"realm": definition = CultivationRealmDefinition.new()
		"foundation": definition = DaoFoundationDefinition.new()
		"actor": definition = ActorDefinition.new()
		"npc": definition = NpcDefinition.new()
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
	if definition is ItemDefinition:
		if not _configure_item_definition(
			definition as ItemDefinition,
			options,
			diagnostics,
			content_id
		):
			return null
	elif definition is SkillDefinition:
		var skill_icon_path := String(options.get("icon", ""))
		if not skill_icon_path.is_empty():
			(definition as SkillDefinition).icon = load(skill_icon_path) as Texture2D
			if (definition as SkillDefinition).icon == null:
				diagnostics.append(_diagnostic(
					"skill_icon_invalid",
					"icon must reference a Texture2D",
					skill_icon_path,
					"icon",
					String(content_id)
				))
				return null
	if definition is CultivationRealmDefinition:
		var realm := definition as CultivationRealmDefinition
		realm.max_layer = int(options.get("max_layer", "1"))
		var costs := PackedInt32Array()
		var raw_costs := String(options.get("layer_costs", ""))
		if not raw_costs.is_empty():
			for raw_cost: String in raw_costs.split(",", false):
				if (
					not raw_cost.strip_edges().is_valid_int()
					or int(raw_cost.strip_edges()) <= 0
				):
					diagnostics.append(_diagnostic(
						"realm_layer_costs_invalid",
						"layer_costs must be comma-separated positive integers",
						String(options.get("path", "")),
						"layer_cultivation_costs",
						String(content_id)
					))
					return null
				costs.append(int(raw_cost.strip_edges()))
		if realm.max_layer < 1 or costs.size() != realm.max_layer - 1:
			diagnostics.append(_diagnostic(
				"realm_layer_cost_count_invalid",
				"layer_costs must contain exactly max_layer - 1 positive integers",
				String(options.get("path", "")),
				"layer_cultivation_costs",
				String(content_id)
			))
			return null
		realm.layer_cultivation_costs = costs
		realm.breakthrough_cultivation_required = int(options.get("breakthrough_cultivation", "0"))
		realm.base_max_hp_bonus = int(options.get("base_hp_bonus", "0"))
		realm.base_max_mp_bonus = int(options.get("base_mp_bonus", "0"))
		realm.base_attack_bonus = int(options.get("base_attack_bonus", "0"))
		realm.max_hp_bonus_per_layer = int(options.get("hp_bonus_per_layer", "0"))
		realm.max_mp_bonus_per_layer = int(options.get("mp_bonus_per_layer", "0"))
		realm.attack_bonus_per_layer = int(options.get("attack_bonus_per_layer", "0"))
		var next_realm_path := String(options.get("next_realm", ""))
		if not next_realm_path.is_empty():
			realm.next_realm = load(next_realm_path) as CultivationRealmDefinition
			if realm.next_realm == null:
				diagnostics.append(_diagnostic(
					"realm_next_realm_invalid",
					"next_realm must reference a CultivationRealmDefinition",
					next_realm_path,
					"next_realm",
					String(content_id)
				))
				return null
	elif definition is DaoFoundationDefinition:
		var dao_foundation := definition as DaoFoundationDefinition
		var foundation_realm_path := String(options.get("realm", ""))
		dao_foundation.required_realm = (
			load(foundation_realm_path) as CultivationRealmDefinition
			if not foundation_realm_path.is_empty()
			else null
		)
		if dao_foundation.required_realm == null:
			diagnostics.append(_diagnostic(
				"foundation_realm_invalid",
				"foundation create requires --realm with a CultivationRealmDefinition path",
				foundation_realm_path,
				"required_realm",
				String(content_id)
			))
			return null
		dao_foundation.max_hp_bonus = int(options.get(
			"max_hp_bonus",
			options.get("base_hp_bonus", "0")
		))
		dao_foundation.max_mp_bonus = int(options.get(
			"max_mp_bonus",
			options.get("base_mp_bonus", "0")
		))
		dao_foundation.attack_bonus = int(options.get(
			"attack_bonus",
			options.get("base_attack_bonus", "0")
		))
	elif definition is ActorDefinition:
		var actor := definition as ActorDefinition
		actor.base_max_hp = int(options.get("max_hp", "100"))
		actor.base_max_mp = int(options.get("max_mp", "20"))
		actor.base_attack = int(options.get("attack", "12"))
		var initial_realm_path := String(options.get("realm", ""))
		actor.initial_realm = (
			load(initial_realm_path) as CultivationRealmDefinition
			if not initial_realm_path.is_empty()
			else null
		)
		if actor.initial_realm == null:
			diagnostics.append(_diagnostic(
				"actor_realm_invalid",
				"actor create requires --realm with a CultivationRealmDefinition path",
				initial_realm_path,
				"initial_realm",
				String(content_id)
			))
			return null
		actor.initial_realm_layer = int(options.get("realm_layer", "1"))
		actor.initial_cultivation_points = int(options.get("cultivation_points", "0"))
		actor.equipment_slots.clear()
		for raw_slot: String in String(options.get("equipment_slots", "weapon")).split(",", false):
			actor.equipment_slots.append(StringName(raw_slot.strip_edges()))
		if (
			actor.initial_realm_layer < 1
			or actor.initial_realm_layer > actor.initial_realm.max_layer
			or actor.initial_cultivation_points < 0
		):
			diagnostics.append(_diagnostic(
				"actor_cultivation_invalid",
				"realm_layer and cultivation_points are outside the initial realm",
				String(options.get("path", "")),
				"initial_realm_layer",
				String(content_id)
			))
			return null
		var initial_foundation_path := String(options.get("foundation", ""))
		if not initial_foundation_path.is_empty():
			actor.initial_foundation = load(initial_foundation_path) as DaoFoundationDefinition
			if actor.initial_foundation == null:
				diagnostics.append(_diagnostic(
					"actor_foundation_invalid",
					"foundation must reference a DaoFoundationDefinition",
					initial_foundation_path,
					"initial_foundation",
					String(content_id)
				))
				return null
	elif definition is NpcDefinition:
		var npc := definition as NpcDefinition
		npc.field_model_3d = load(String(options.get("scene", ""))) as PackedScene
		if npc.field_model_3d == null:
			diagnostics.append(_diagnostic(
				"npc_scene_load_failed",
				"npc create requires --scene with a Node3D PackedScene",
				String(options.get("scene", "")),
				"field_model_3d",
				String(content_id)
			))
			return null
		var npc_instance := npc.field_model_3d.instantiate()
		if not npc_instance is Node3D:
			diagnostics.append(_diagnostic(
				"npc_scene_type_invalid",
				"npc field_model_3d root must inherit Node3D",
				String(options.get("scene", "")),
				"field_model_3d",
				String(content_id)
			))
			npc_instance.free()
			return null
		npc_instance.free()
	elif definition is EquipmentDefinition:
		var equipment := definition as EquipmentDefinition
		equipment.slot = StringName(options.get("slot", "weapon"))
	elif definition is ItemDefinition:
		pass
	elif definition is SkillDefinition:
		var skill := definition as SkillDefinition
		skill.mp_cost = int(options.get("mp_cost", "0"))
		var target_rule := _parse_target_rule(String(options.get("target_rule", "direction")))
		if target_rule < 0:
			diagnostics.append(_diagnostic(
				"skill_target_rule_invalid",
				"target_rule must be self, single_enemy, direction, point, or area",
				String(options.get("path", "")),
				"target_rule",
				String(content_id)
			))
			return null
		skill.target_rule = target_rule as SkillDefinition.TargetRule
		skill.cooldown_seconds = float(options.get("cooldown_seconds", "0"))
		skill.cast_seconds = float(options.get("cast_seconds", "0"))
		skill.active_seconds = float(options.get("active_seconds", "0.1"))
		skill.recovery_seconds = float(options.get("recovery_seconds", "0.2"))
		skill.max_range = float(options.get("max_range", "1.5"))
		skill.radius = float(options.get("radius", "0"))
		var presentation_path := String(options.get("presentation_scene", ""))
		if not presentation_path.is_empty():
			skill.presentation_scene = load(presentation_path) as PackedScene
			if skill.presentation_scene == null:
				diagnostics.append(_diagnostic(
					"skill_presentation_scene_invalid",
					"presentation_scene must reference a PackedScene",
					presentation_path,
					"presentation_scene",
					String(content_id)
				))
				return null
		var sound_path := String(options.get("sound", ""))
		if not sound_path.is_empty():
			skill.sound = load(sound_path) as AudioStream
			if skill.sound == null:
				diagnostics.append(_diagnostic(
					"skill_sound_invalid",
					"sound must reference an AudioStream",
					sound_path,
					"sound",
					String(content_id)
				))
				return null
	elif definition is StatusDefinition:
		var status := definition as StatusDefinition
		status.duration_seconds = float(options.get("duration_seconds", "1"))
		status.tick_interval_seconds = float(options.get("tick_interval_seconds", "1"))
		status.periodic_damage = int(options.get("periodic_damage", "0"))
	elif definition is EnemyDefinition:
		var enemy := definition as EnemyDefinition
		enemy.max_hp = int(options.get("max_hp", "30"))
		enemy.attack = int(options.get("attack", "8"))
		enemy.move_speed = float(options.get("move_speed", "3"))
		enemy.aggro_range = float(options.get("aggro_range", "8"))
		enemy.attack_range = float(options.get("attack_range", "1.5"))
		enemy.leash_radius = float(options.get("leash_radius", "12"))
		enemy.attack_windup_seconds = float(options.get("attack_windup_seconds", "0.35"))
		enemy.attack_active_seconds = float(options.get("attack_active_seconds", "0.1"))
		enemy.attack_recovery_seconds = float(options.get("attack_recovery_seconds", "0.45"))
		enemy.cultivation_reward = int(options.get("cultivation_reward", "0"))
		enemy.money_reward = int(options.get("money_reward", "0"))
		enemy.drop_quantity = int(options.get("drop_quantity", "0"))
		var drop_path := String(options.get("drop_item", ""))
		if not drop_path.is_empty():
			enemy.drop_item = load(drop_path) as ItemDefinition
			if enemy.drop_item == null:
				diagnostics.append(_diagnostic(
					"enemy_drop_item_invalid",
					"drop_item must reference an ItemDefinition",
					drop_path,
					"drop_item",
					String(content_id)
				))
				return null
		enemy.character_scene = load(String(options.get("scene", ""))) as PackedScene
		if enemy.character_scene == null:
			diagnostics.append(_diagnostic(
				"enemy_scene_load_failed",
				"enemy create requires --scene with a CharacterBody3D PackedScene",
				String(options.get("scene", "")),
				"character_scene",
				String(content_id)
			))
			return null
		var enemy_instance := enemy.character_scene.instantiate()
		if not enemy_instance is CharacterBody3D:
			diagnostics.append(_diagnostic(
				"enemy_scene_type_invalid",
				"enemy character_scene root must inherit CharacterBody3D",
				String(options.get("scene", "")),
				"character_scene",
				String(content_id)
			))
			enemy_instance.free()
			return null
		enemy_instance.free()
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
		encounter_enemy.spawn_offset = Vector3(
			float(options.get("spawn_x", "0")),
			float(options.get("spawn_y", "0")),
			float(options.get("spawn_z", "0"))
		)
		encounter_enemy.level_modifier = int(options.get("level_modifier", "0"))
		var encounter := definition as BattleEncounter
		encounter.enemies.assign([encounter_enemy])
		var allows_escape: Variant = _parse_bool(String(options.get("allows_escape", "true")))
		if allows_escape == null:
			diagnostics.append(_diagnostic(
				"encounter_allows_escape_invalid",
				"allows_escape must be true or false",
				String(options.get("path", "")),
				"allows_escape",
				String(content_id)
			))
			return null
		encounter.allows_escape = bool(allows_escape)
		encounter.encounter_radius = float(options.get("encounter_radius", "10"))
		encounter.leash_radius = float(options.get("leash_radius", "14"))
		var reward_policy := _parse_reward_policy(String(options.get(
			"reward_policy", "all_or_nothing"
		)))
		if reward_policy < 0:
			diagnostics.append(_diagnostic(
				"encounter_reward_policy_invalid",
				"reward_policy must be all_or_nothing or allow_partial",
				String(options.get("path", "")),
				"reward_policy",
				String(content_id)
			))
			return null
		encounter.reward_policy = reward_policy as RewardPolicy.Value
		var music_path := String(options.get("battle_music", ""))
		if not music_path.is_empty():
			encounter.battle_music = load(music_path) as AudioStream
			if encounter.battle_music == null:
				diagnostics.append(_diagnostic(
					"encounter_battle_music_invalid",
					"battle_music must reference an AudioStream",
					music_path,
					"battle_music",
					String(content_id)
				))
				return null
	return definition


func _parse_target_rule(value: String) -> int:
	var normalized := value.strip_edges().to_lower().replace("-", "_")
	var names := {
		"self": SkillDefinition.TargetRule.SELF,
		"single_enemy": SkillDefinition.TargetRule.SINGLE_ENEMY,
		"direction": SkillDefinition.TargetRule.DIRECTION,
		"point": SkillDefinition.TargetRule.POINT,
		"area": SkillDefinition.TargetRule.AREA,
	}
	return int(names.get(normalized, -1))


func _parse_reward_policy(value: String) -> int:
	match value.strip_edges().to_lower().replace("-", "_"):
		"all_or_nothing":
			return RewardPolicy.Value.ALL_OR_NOTHING
		"allow_partial":
			return RewardPolicy.Value.ALLOW_PARTIAL
	return -1


func _parse_bool(value: String) -> Variant:
	match value.strip_edges().to_lower():
		"true":
			return true
		"false":
			return false
	return null


func _configure_item_definition(
	item: ItemDefinition,
	options: Dictionary,
	diagnostics: Array[Dictionary],
	content_id: StringName
) -> bool:
	item.price = int(options.get("price", "0"))
	if not item is EquipmentDefinition:
		item.max_stack = int(options.get("max_stack", "9"))
	var can_discard: Variant = _parse_bool(String(options.get("can_discard", "true")))
	var can_sell: Variant = _parse_bool(String(options.get("can_sell", "true")))
	if can_discard == null or can_sell == null:
		diagnostics.append(_diagnostic(
			"item_permission_invalid",
			"can_discard and can_sell must be true or false",
			String(options.get("path", "")),
			"can_discard" if can_discard == null else "can_sell",
			String(content_id)
		))
		return false
	item.can_discard = bool(can_discard)
	item.can_sell = bool(can_sell)
	var icon_path := String(options.get("icon", ""))
	if not icon_path.is_empty():
		item.icon = load(icon_path) as Texture2D
		if item.icon == null:
			diagnostics.append(_diagnostic(
				"item_icon_invalid",
				"icon must reference a Texture2D",
				icon_path,
				"icon",
				String(content_id)
			))
			return false
	return true


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
	if not instance is MapGameScene3D:
		diagnostics.append(_diagnostic(
			"map_scene_type_invalid",
			"map scene root must inherit MapGameScene3D",
			scene_path,
			"scene",
			String(content_id)
		))
		instance.free()
		return null
	var default_spawn := StringName(options.get("default_spawn", "start"))
	if instance.get_node_or_null(^"WorldRoot/SpawnPoints") == null or (
		instance.get_node(^"WorldRoot/SpawnPoints").get_node_or_null(
			NodePath(String(default_spawn))
		) == null
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
	var story_path := String(options.get("story", ""))
	if not story_path.is_empty():
		definition.story_module = load(story_path) as StoryModule
		if definition.story_module == null:
			diagnostics.append(_diagnostic(
				"map_story_invalid",
				"story must reference a StoryModule",
				story_path,
				"story_module",
				String(content_id)
			))
			return null
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
