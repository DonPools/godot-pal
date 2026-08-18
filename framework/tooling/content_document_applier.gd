class_name ContentDocumentApplier
extends RefCounted


func apply(document: Dictionary, catalog: ContentCatalog) -> Dictionary:
	if catalog == null:
		return _failure("content_catalog_missing", "content catalog is missing", "", "")
	var raw_content: Variant = document.get("content")
	if not raw_content is Array:
		return _failure("content_json_invalid", "apply document must contain a content array", "", "content")
	var changes: Array[Dictionary] = []
	var diagnostics: Array[Dictionary] = []
	for raw_change: Variant in raw_content:
		_collect_changes(raw_change, catalog, changes, diagnostics)
	if not diagnostics.is_empty():
		return {"ok": false, "code": "content_apply_invalid", "diagnostics": diagnostics}
	if changes.is_empty():
		return {"ok": true, "change_count": 0, "resource_count": 0, "diagnostics": []}
	return _apply_changes(changes, catalog)


func _collect_changes(
	raw_change: Variant,
	catalog: ContentCatalog,
	changes: Array[Dictionary],
	diagnostics: Array[Dictionary]
) -> void:
	if not raw_change is Dictionary:
		diagnostics.append(_diagnostic("content_change_invalid", "content change must be an object", "", "content"))
		return
	var content_type := String(raw_change.get("type", ""))
	var content_id := StringName(raw_change.get("id", ""))
	var properties: Variant = raw_change.get("properties")
	var resource_value := catalog.resource(content_type, content_id)
	if resource_value == null or not properties is Dictionary:
		diagnostics.append(_diagnostic(
			"content_change_target_invalid",
			"change target or properties are invalid",
			"",
			"content",
			String(content_id)
		))
		return
	if resource_value.resource_path.is_empty() or not resource_value.resource_path.begins_with("res://"):
		diagnostics.append(_diagnostic(
			"content_change_path_invalid",
			"content target must be a saved res:// resource",
			resource_value.resource_path,
			"path",
			String(content_id)
		))
		return
	for raw_field: Variant in properties:
		var field := String(raw_field)
		var property := _stored_editor_property(resource_value, field)
		if not raw_field is String or field in ["id", "script"] or property.is_empty():
			diagnostics.append(_diagnostic(
				"content_field_invalid",
				"field is not editable: %s" % field,
				resource_value.resource_path,
				field,
				String(content_id)
			))
			continue
		var converted := _convert_value(properties[raw_field], resource_value.get(field), property)
		if not converted.get("ok", false):
			diagnostics.append(_diagnostic(
				"content_value_invalid",
				"field value has the wrong type: %s" % field,
				resource_value.resource_path,
				field,
				String(content_id)
			))
			continue
		var value: Variant = converted.get("value")
		if resource_value.get(field) != value:
			changes.append({
				"resource": resource_value,
				"field": field,
				"old_value": resource_value.get(field).duplicate(true) if resource_value.get(field) is Array or resource_value.get(field) is Dictionary else resource_value.get(field),
				"new_value": value,
			})


func _convert_value(value: Variant, current: Variant, property: Dictionary) -> Dictionary:
	var type := int(property.get("type", TYPE_NIL))
	match type:
		TYPE_BOOL:
			return {"ok": value is bool, "value": value}
		TYPE_INT:
			if value is int:
				return {"ok": true, "value": value}
			if value is float and is_equal_approx(value, roundf(value)):
				return {"ok": true, "value": int(value)}
			if value is String and int(property.get("hint", PROPERTY_HINT_NONE)) == PROPERTY_HINT_ENUM:
				var enum_value := _enum_index(String(value), String(property.get("hint_string", "")))
				if enum_value >= 0:
					return {"ok": true, "value": enum_value}
		TYPE_FLOAT:
			if value is int or value is float:
				return {"ok": true, "value": float(value)}
		TYPE_STRING:
			return {"ok": value is String, "value": value}
		TYPE_STRING_NAME:
			return {"ok": value is String, "value": StringName(value)}
		TYPE_ARRAY:
			if not value is Array:
				return {"ok": false}
			var converted: Array = current.duplicate(true)
			converted.clear()
			var typed_as_string_names := current is Array[StringName]
			for element: Variant in value:
				if typed_as_string_names:
					if not element is String:
						return {"ok": false}
					converted.append(StringName(element))
				elif element == null or element is bool or element is int or element is float or element is String:
					converted.append(element)
				else:
					return {"ok": false}
			return {"ok": true, "value": converted}
	return {"ok": false}


func _enum_index(value: String, hint: String) -> int:
	var normalized := value.strip_edges().to_lower().replace("-", "_")
	var options := hint.split(",", false)
	for index: int in range(options.size()):
		var option := String(options[index]).strip_edges()
		var name := option.get_slice(":", 0).to_lower().replace("-", "_")
		if name == normalized:
			return int(option.get_slice(":", 1)) if option.contains(":") else index
	return -1


func _apply_changes(changes: Array[Dictionary], catalog: ContentCatalog) -> Dictionary:
	var database := catalog.database
	var resources: Dictionary[int, Resource] = {}
	for change: Dictionary in changes:
		var resource_value := change["resource"] as Resource
		resource_value.set(change["field"], change["new_value"])
		resources[resource_value.get_instance_id()] = resource_value
	var validation_errors := _content_errors(catalog)
	if not validation_errors.is_empty():
		_restore_values(changes)
		if database != null:
			database.build_index()
		return _failure(
			"content_validation_failed",
			String(validation_errors[0]),
			database.resource_path if database != null else "",
			""
		)
	var temporary_paths: Dictionary[String, String] = {}
	for resource_value: Resource in resources.values():
		var path := resource_value.resource_path
		var temporary := "%s.apply.tmp.%s" % [path.get_basename(), path.get_extension()]
		var save_error := ResourceSaver.save(resource_value, temporary)
		if save_error != OK:
			_restore_values(changes)
			if database != null:
				database.build_index()
			_cleanup_paths(temporary_paths.values())
			return _failure(
				"content_save_failed",
				"could not prepare content update: %s" % error_string(save_error),
				path,
				""
			)
		temporary_paths[path] = temporary
	var installed: Array[String] = []
	for path: String in temporary_paths:
		var backup := "%s.apply.bak" % path
		var backup_error := DirAccess.rename_absolute(
			ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(backup)
		)
		if backup_error != OK:
			_rollback_files(installed, temporary_paths)
			_restore_values(changes)
			return _failure("content_backup_failed", "could not back up content resource", path, "")
		var install_error := DirAccess.rename_absolute(
			ProjectSettings.globalize_path(temporary_paths[path]),
			ProjectSettings.globalize_path(path)
		)
		if install_error != OK:
			DirAccess.rename_absolute(
				ProjectSettings.globalize_path(backup), ProjectSettings.globalize_path(path)
			)
			_rollback_files(installed, temporary_paths)
			_restore_values(changes)
			return _failure("content_replace_failed", "could not install content resource", path, "")
		installed.append(path)
	for path: String in installed:
		var backup := "%s.apply.bak" % path
		if FileAccess.file_exists(backup):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(backup))
	return {
		"ok": true,
		"change_count": changes.size(),
		"resource_count": resources.size(),
		"diagnostics": [],
	}


func _stored_editor_property(resource_value: Resource, field: String) -> Dictionary:
	for property: Dictionary in resource_value.get_property_list():
		var usage := int(property.get("usage", 0))
		if (
			String(property.get("name", "")) == field
			and (usage & PROPERTY_USAGE_STORAGE) != 0
			and (usage & PROPERTY_USAGE_EDITOR) != 0
		):
			return property
	return {}


func _content_errors(catalog: ContentCatalog) -> PackedStringArray:
	var errors := PackedStringArray()
	var database := catalog.database
	if database == null:
		errors.append("content catalog has no ContentDatabase")
		return errors
	errors.append_array(database.build_index())
	var stories: Array[StoryModule] = []
	for record: Dictionary in catalog.items:
		var resource_value := record.get("resource") as Resource
		if resource_value is StoryModule:
			var story := resource_value as StoryModule
			stories.append(story)
			if story.initial_stage.is_empty() or story.initial_stage not in story.valid_stages:
				errors.append("Story %s has an invalid initial_stage" % story.id)
			var stages: Dictionary[StringName, bool] = {}
			for stage_id: StringName in story.valid_stages:
				if stage_id.is_empty() or stages.has(stage_id):
					errors.append("Story %s has an empty or repeated stage" % story.id)
				stages[stage_id] = true
		elif resource_value is DialogueDefinition:
			errors.append_array((resource_value as DialogueDefinition).validate())
	errors.append_array(MapSceneValidator.new().validate(database, stories))
	return errors


func _restore_values(changes: Array[Dictionary]) -> void:
	for change: Dictionary in changes:
		(change["resource"] as Resource).set(change["field"], change["old_value"])


func _rollback_files(installed: Array[String], temporary_paths: Dictionary[String, String]) -> void:
	for path: String in installed:
		var backup := "%s.apply.bak" % path
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if FileAccess.file_exists(backup):
			DirAccess.rename_absolute(
				ProjectSettings.globalize_path(backup), ProjectSettings.globalize_path(path)
			)
	_cleanup_paths(temporary_paths.values())


func _cleanup_paths(paths: Array) -> void:
	for path: String in paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _failure(code: String, message: String, file: String, field: String) -> Dictionary:
	return {
		"ok": false,
		"code": code,
		"diagnostics": [_diagnostic(code, message, file, field)],
	}


func _diagnostic(
	code: String,
	message: String,
	file: String,
	field: String,
	content_id: String = ""
) -> Dictionary:
	var result := {"code": code, "message": message, "file": file, "field": field}
	if not content_id.is_empty():
		result["content_id"] = content_id
	return result
