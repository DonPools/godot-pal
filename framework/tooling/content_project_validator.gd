class_name ContentProjectValidator
extends RefCounted


static func validate(
	database: ContentDatabase,
	database_path: String
) -> Array[Dictionary]:
	var diagnostics: Array[Dictionary] = []
	for message: String in database.build_index():
		diagnostics.append(_diagnostic(
			"content_database_invalid",
			message,
			database_path,
			"maps"
		))
	var scanned := ContentSourceScanner.new().scan_story_resources(
		database.story_directories
	)
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
			_map_file_for_message(database, database_path, message),
			"scene"
		))
	_validate_embedded_bindings(database, diagnostics)
	return diagnostics


static func _validate_stories(
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
				"StoryModule initial_stage is not listed in valid_stages: %s"
				% story.initial_stage,
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


static func _validate_dialogues(
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
				"DialogueDefinition id must use the dialogue.* namespace: %s"
				% dialogue.id,
				path,
				"id",
				String(dialogue.id)
			))
		elif ids.has(dialogue.id):
			diagnostics.append(_diagnostic(
				"dialogue_id_duplicate",
				"DialogueDefinition id is repeated; first declared in %s"
				% ids[dialogue.id],
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


static func _validate_embedded_bindings(
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
		elif (
			binding.trigger_id.is_empty()
			or binding.trigger_id not in binding.event.get_trigger_ids()
		):
			diagnostics.append(_diagnostic(
				"story_binding_trigger_invalid",
				"StoryBinding references an unknown trigger: %s" % binding.trigger_id,
				file,
				field,
				String(record.get("map_id", ""))
			))


static func _valid_id(content_id: String, prefix: String) -> bool:
	if not content_id.begins_with(prefix + ".") or content_id != content_id.to_lower():
		return false
	for part: String in content_id.split("."):
		if part.is_empty() or not part.is_valid_identifier():
			return false
	return true


static func _map_file_for_message(
	database: ContentDatabase,
	database_path: String,
	message: String
) -> String:
	for definition: MapDefinition in database.maps:
		if definition != null and message.begins_with("map %s " % definition.id):
			return (
				definition.scene.resource_path
				if definition.scene != null
				else definition.resource_path
			)
	return database_path


static func _diagnostic(
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
