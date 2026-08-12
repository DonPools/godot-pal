class_name ContentSourceScanner
extends RefCounted

const STORIES_ROOT := "res://stories"


func scan_story_resources() -> Dictionary:
	var paths := PackedStringArray()
	_collect_resource_paths(STORIES_ROOT, paths)
	paths.sort()
	var stories: Array[StoryModule] = []
	var dialogues: Array[DialogueDefinition] = []
	var diagnostics: Array[Dictionary] = []
	for path: String in paths:
		var resource := load(path)
		if resource == null:
			diagnostics.append({
				"code": "content_resource_load_failed",
				"message": "content resource could not be loaded",
				"file": path,
				"field": "",
			})
		elif resource is StoryModule:
			stories.append(resource)
		elif resource is DialogueDefinition:
			dialogues.append(resource)
	return {
		"stories": stories,
		"dialogues": dialogues,
		"diagnostics": diagnostics,
	}


func scan_embedded_bindings(database: ContentDatabase) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if database == null:
		return result
	for definition: MapDefinition in database.maps:
		if definition == null or definition.scene == null:
			continue
		var instance := definition.scene.instantiate()
		_collect_node_bindings(definition, instance, instance, result)
		instance.free()
	return result


func _collect_resource_paths(directory_path: String, result: PackedStringArray) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return
	var files := directory.get_files()
	files.sort()
	for file_name: String in files:
		if file_name.get_extension().to_lower() == "tres":
			result.append(directory_path.path_join(file_name))
	var directories := directory.get_directories()
	directories.sort()
	for child_name: String in directories:
		if not child_name.begins_with("."):
			_collect_resource_paths(directory_path.path_join(child_name), result)


func _collect_node_bindings(
	definition: MapDefinition,
	root: Node,
	node: Node,
	result: Array[Dictionary]
) -> void:
	for property: Dictionary in node.get_property_list():
		if (int(property.get("usage", 0)) & PROPERTY_USAGE_EDITOR) == 0:
			continue
		var property_name := StringName(property.get("name", ""))
		var value: Variant = node.get(property_name)
		if value is StoryBinding:
			_append_binding(definition, root, node, property_name, value, result)
		elif value is Array:
			for index: int in range(value.size()):
				if value[index] is StoryBinding:
					_append_binding(
						definition,
						root,
						node,
						StringName("%s[%d]" % [property_name, index]),
						value[index],
						result
					)
	for child: Node in node.get_children():
		_collect_node_bindings(definition, root, child, result)


func _append_binding(
	definition: MapDefinition,
	root: Node,
	node: Node,
	field: StringName,
	binding: StoryBinding,
	result: Array[Dictionary]
) -> void:
	result.append({
		"map_id": definition.id,
		"file": definition.scene.resource_path,
		"node_path": root.get_path_to(node),
		"field": field,
		"binding": binding,
	})
