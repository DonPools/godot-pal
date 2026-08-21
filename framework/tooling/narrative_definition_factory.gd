class_name NarrativeDefinitionFactory
extends RefCounted

const CONTENT_TYPES := ["dialogue", "story"]


static func supports(content_type: String) -> bool:
	return content_type in CONTENT_TYPES


static func create(
	content_type: String,
	content_id: StringName,
	options: Dictionary
) -> ContentCreationResult:
	var result := ContentCreationResult.new()
	match content_type:
		"dialogue":
			result.resource = _create_dialogue(content_id, options)
		"story":
			result.resource = _create_story(content_id, options, result)
		_:
			result.reject(
				"content_type_unsupported",
				"narrative factory does not support %s" % content_type,
				"",
				"type",
				content_id
			)
	return result


static func _create_dialogue(
	content_id: StringName,
	options: Dictionary
) -> DialogueDefinition:
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


static func _create_story(
	content_id: StringName,
	options: Dictionary,
	result: ContentCreationResult
) -> StoryModule:
	var story: StoryModule
	var script_path := String(options.get("script", ""))
	if script_path.is_empty():
		story = StoryModule.new()
	else:
		var script := load(script_path) as Script
		if script == null or not script.can_instantiate():
			result.reject(
				"story_script_load_failed",
				"story --script must be an instantiable GDScript",
				script_path,
				"script",
				content_id
			)
			return null
		story = script.new() as StoryModule
		if story == null:
			result.reject(
				"story_script_type_invalid",
				"story --script must extend StoryModule",
				script_path,
				"script",
				content_id
			)
			return null
	story.id = content_id
	story.initial_stage = StringName(options.get("initial_stage", "not_started"))
	var stages := PackedStringArray(
		String(options.get("stages", "not_started")).split(",", false)
	)
	for stage: String in stages:
		story.valid_stages.append(StringName(stage.strip_edges()))
	if story.initial_stage not in story.valid_stages:
		result.reject(
			"story_initial_stage_invalid",
			"story initial stage must appear in --stages",
			String(options.get("path", "")),
			"initial_stage",
			content_id
		)
		return null
	var dialogue_path := String(options.get("dialogue", ""))
	if not dialogue_path.is_empty():
		story.dialogue = load(dialogue_path) as DialogueDefinition
		if story.dialogue == null:
			result.reject(
				"story_dialogue_load_failed",
				"story --dialogue must reference a DialogueDefinition",
				dialogue_path,
				"dialogue",
				content_id
			)
			return null
	return story
