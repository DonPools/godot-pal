extends SceneTree

const CONTRACT_VERSION := 1
const DATABASE_PATH := "res://content/content_database.tres"
const MANIFEST_PATH := "res://generated/manifest.json"
const GENERATED_ROOT := "res://generated/"
const CONTENT_TYPES := ["map", "dialogue", "story"]

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
		_finish_usage("usage: content_cli.gd -- list [map|dialogue|story] [--json]")
		return
	var requested_type := arguments[1] if arguments.size() == 2 else "all"
	if requested_type != "all" and requested_type not in CONTENT_TYPES:
		_finish_usage("unknown content type: %s" % requested_type)
		return
	var snapshot := _content_snapshot()
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
		_finish_usage("usage: content_cli.gd -- show <map|dialogue|story> <id> [--json]")
		return
	var content_type := arguments[1]
	var content_id := StringName(arguments[2])
	var found := _find_content(content_type, content_id)
	var diagnostics: Array[Dictionary] = []
	diagnostics.assign(found.get("diagnostics", []))
	if not diagnostics.is_empty():
		_finish_content_error("show", diagnostics)
		return
	var item: Variant = found.get("item")
	if not item is Dictionary:
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
		_finish_usage("usage: content_cli.gd -- schema [map|dialogue|story] [--json]")
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
			"usage: content_cli.gd -- create <map|dialogue|story> <id> "
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
			"register the MapDefinition in content/content_database.tres"
			if content_type == "map"
			else "reference the resource from a map binding or story"
		),
		"diagnostics": [],
	})


func _validate_content() -> Array[Dictionary]:
	var diagnostics: Array[Dictionary] = []
	diagnostics.append_array(
		AssetManifestValidator.new().validate_file(MANIFEST_PATH, GENERATED_ROOT)["diagnostics"]
	)
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


func _content_snapshot() -> Dictionary:
	var diagnostics: Array[Dictionary] = []
	var items: Array[Dictionary] = []
	var database := load(DATABASE_PATH) as ContentDatabase
	if database == null:
		diagnostics.append(_diagnostic(
			"content_database_load_failed",
			"content database could not be loaded",
			DATABASE_PATH,
			""
		))
		return {"items": items, "diagnostics": diagnostics}
	for message: String in database.build_index():
		diagnostics.append(_diagnostic(
			"content_database_invalid", message, DATABASE_PATH, "maps"
		))
	for definition: MapDefinition in database.maps:
		if definition != null:
			items.append(_map_summary(definition))
	var scanned := ContentSourceScanner.new().scan_story_resources()
	diagnostics.append_array(scanned.get("diagnostics", []))
	var stories: Array[StoryModule] = []
	stories.assign(scanned.get("stories", []))
	for story: StoryModule in stories:
		items.append(_story_summary(story))
	var seen_dialogues: Dictionary[String, bool] = {}
	var dialogues: Array[DialogueDefinition] = []
	dialogues.assign(scanned.get("dialogues", []))
	for story: StoryModule in stories:
		if story.dialogue != null:
			dialogues.append(story.dialogue)
	for dialogue: DialogueDefinition in dialogues:
		var key := dialogue.resource_path if not dialogue.resource_path.is_empty() else String(dialogue.id)
		if not seen_dialogues.has(key):
			seen_dialogues[key] = true
			items.append(_dialogue_summary(dialogue))
	return {"items": items, "diagnostics": diagnostics}


func _find_content(content_type: String, content_id: StringName) -> Dictionary:
	var snapshot := _content_snapshot()
	var diagnostics: Array[Dictionary] = []
	diagnostics.assign(snapshot.get("diagnostics", []))
	if not diagnostics.is_empty():
		return {"item": null, "diagnostics": diagnostics}
	if content_type == "map":
		var database := load(DATABASE_PATH) as ContentDatabase
		database.build_index()
		var definition := database.map(content_id)
		return {
			"item": _map_details(definition) if definition != null else null,
			"diagnostics": [],
		}
	var scanned := ContentSourceScanner.new().scan_story_resources()
	if content_type == "story":
		var stories: Array[StoryModule] = []
		stories.assign(scanned.get("stories", []))
		for story: StoryModule in stories:
			if story.id == content_id:
				return {"item": _story_details(story), "diagnostics": []}
	else:
		var dialogues: Array[DialogueDefinition] = []
		dialogues.assign(scanned.get("dialogues", []))
		for story: StoryModule in scanned.get("stories", []):
			if story.dialogue != null:
				dialogues.append(story.dialogue)
		for dialogue: DialogueDefinition in dialogues:
			if dialogue.id == content_id:
				return {"item": _dialogue_details(dialogue), "diagnostics": []}
	return {"item": null, "diagnostics": []}


func _map_summary(definition: MapDefinition) -> Dictionary:
	return {
		"type": "map",
		"id": String(definition.id),
		"path": definition.resource_path,
		"display_name": definition.display_name,
	}


func _map_details(definition: MapDefinition) -> Dictionary:
	return {
		"type": "map",
		"id": String(definition.id),
		"path": definition.resource_path,
		"display_name": definition.display_name,
		"description": definition.description,
		"tags": _string_names(definition.tags),
		"scene": definition.scene.resource_path if definition.scene != null else "",
		"default_spawn_id": String(definition.default_spawn_id),
		"music_source_id": definition.music_source_id,
	}


func _dialogue_summary(dialogue: DialogueDefinition) -> Dictionary:
	return {
		"type": "dialogue",
		"id": String(dialogue.id),
		"path": dialogue.resource_path,
		"block_count": dialogue.blocks.size(),
	}


func _dialogue_details(dialogue: DialogueDefinition) -> Dictionary:
	var blocks: Array[Dictionary] = []
	for block: DialogueBlock in dialogue.blocks:
		blocks.append({
			"id": String(block.id) if block != null else "",
			"entry_count": block.entries.size() if block != null else 0,
		})
	return {
		"type": "dialogue",
		"id": String(dialogue.id),
		"path": dialogue.resource_path,
		"blocks": blocks,
	}


func _story_summary(story: StoryModule) -> Dictionary:
	return {
		"type": "story",
		"id": String(story.id),
		"path": story.resource_path,
		"initial_stage": String(story.initial_stage),
	}


func _story_details(story: StoryModule) -> Dictionary:
	return {
		"type": "story",
		"id": String(story.id),
		"path": story.resource_path,
		"initial_stage": String(story.initial_stage),
		"valid_stages": _string_names(story.valid_stages),
		"trigger_ids": _string_names(story.get_trigger_ids()),
		"dialogue_id": String(story.dialogue.id) if story.dialogue != null else "",
		"dialogue_path": story.dialogue.resource_path if story.dialogue != null else "",
	}


func _schema_for(content_type: String) -> Dictionary:
	match content_type:
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
					_field("music_source_id", "int", false, 31),
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
			"path", "scene", "display_name", "default_spawn", "music_source",
			"block", "speaker", "text", "script", "dialogue", "initial_stage", "stages",
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
	if not _valid_id(String(content_id), content_type):
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
	if existing.get("item") is Dictionary:
		diagnostics.append(_diagnostic(
			"content_id_exists",
			"content id already exists",
			String(existing.get("item", {}).get("path", "")),
			"id",
			String(content_id)
		))
	return diagnostics


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
	definition.music_source_id = int(options.get("music_source", "31"))
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
