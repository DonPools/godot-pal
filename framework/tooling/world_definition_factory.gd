class_name WorldDefinitionFactory
extends RefCounted

const CONTENT_TYPES := ["npc", "map"]


static func supports(content_type: String) -> bool:
	return content_type in CONTENT_TYPES


static func create(
	content_type: String,
	content_id: StringName,
	options: Dictionary
) -> ContentCreationResult:
	var result := ContentCreationResult.new()
	match content_type:
		"npc":
			result.resource = _create_npc(content_id, options, result)
		"map":
			result.resource = _create_map(content_id, options, result)
		_:
			result.reject(
				"content_type_unsupported",
				"world factory does not support %s" % content_type,
				"",
				"type",
				content_id
			)
	return result


static func _create_npc(
	content_id: StringName,
	options: Dictionary,
	result: ContentCreationResult
) -> NpcDefinition:
	var scene_path := String(options.get("scene", ""))
	var scene := load(scene_path) as PackedScene
	if scene == null:
		result.reject(
			"npc_scene_load_failed",
			"npc create requires --scene with a Node3D PackedScene",
			scene_path,
			"field_model_3d",
			content_id
		)
		return null
	var instance := scene.instantiate()
	if not instance is Node3D:
		result.reject(
			"npc_scene_type_invalid",
			"npc field_model_3d root must inherit Node3D",
			scene_path,
			"field_model_3d",
			content_id
		)
		instance.free()
		return null
	instance.free()
	var definition := NpcDefinition.new()
	_configure_common_fields(definition, content_id, options)
	definition.field_model_3d = scene
	return definition


static func _create_map(
	content_id: StringName,
	options: Dictionary,
	result: ContentCreationResult
) -> MapDefinition:
	var scene_path := String(options.get("scene", ""))
	var scene := load(scene_path) as PackedScene
	if scene == null:
		result.reject(
			"map_scene_load_failed",
			"map create requires a valid --scene PackedScene",
			scene_path,
			"scene",
			content_id
		)
		return null
	var instance := scene.instantiate()
	if not instance is MapGameScene3D:
		result.reject(
			"map_scene_type_invalid",
			"map scene root must inherit MapGameScene3D",
			scene_path,
			"scene",
			content_id
		)
		instance.free()
		return null
	var default_spawn := StringName(options.get("default_spawn", "default"))
	var spawn_root := instance.get_node_or_null(^"WorldRoot/SpawnPoints")
	if (
		spawn_root == null
		or spawn_root.get_node_or_null(NodePath(String(default_spawn))) == null
	):
		result.reject(
			"map_default_spawn_invalid",
			"map scene does not contain default spawn: %s" % default_spawn,
			scene_path,
			"default_spawn_id",
			content_id
		)
		instance.free()
		return null
	instance.free()
	var definition := MapDefinition.new()
	_configure_common_fields(definition, content_id, options)
	definition.scene = scene
	definition.default_spawn_id = default_spawn
	var story_path := String(options.get("story", ""))
	if not story_path.is_empty():
		definition.story_module = load(story_path) as StoryModule
		if definition.story_module == null:
			result.reject(
				"map_story_invalid",
				"story must reference a StoryModule",
				story_path,
				"story_module",
				content_id
			)
			return null
	return definition


static func _configure_common_fields(
	definition: ContentDefinition,
	content_id: StringName,
	options: Dictionary
) -> void:
	definition.id = content_id
	definition.display_name = String(options.get(
		"display_name",
		String(content_id).get_slice(".", String(content_id).get_slice_count(".") - 1)
	))
	definition.description = String(options.get("description", "TODO"))
