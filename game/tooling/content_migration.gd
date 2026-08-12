class_name ContentMigration
extends RefCounted


func rename_id(
	content_type: String,
	old_id: StringName,
	new_id: StringName,
	database: ContentDatabase,
	migration_directory: String = "res://content/migrations"
) -> Dictionary:
	var catalog := ContentCatalog.new()
	catalog.build(database)
	var resource_value := catalog.resource(content_type, old_id)
	if resource_value == null:
		return _result(false, "content_not_found", "content ID does not exist: %s" % old_id, [])
	if not catalog.find(content_type, new_id).is_empty():
		return _result(false, "content_id_exists", "target content ID already exists: %s" % new_id, [])
	var id_prefix := "item" if content_type == "equipment" else content_type
	if not _valid_id(String(new_id), id_prefix):
		return _result(false, "content_id_invalid", "target ID must use %s.*" % id_prefix, [])
	var affected := catalog.refs_to(old_id, database)
	var paths: Dictionary[String, bool] = {resource_value.resource_path: true}
	for reference: Dictionary in affected:
		var file := String(reference.get("file", ""))
		if file.begins_with("res://"):
			paths[file] = true
	var originals: Dictionary[String, String] = {}
	for path: String in paths:
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			return _result(false, "migration_read_failed", "could not read %s" % path, affected)
		originals[path] = file.get_as_text()
		file.close()
	var temporary_paths: Dictionary[String, String] = {}
	for path: String in originals:
		var replaced := _replace_serialized_id(originals[path], old_id, new_id)
		if replaced == originals[path]:
			continue
		var temporary := "%s.migrate.tmp" % path
		var file := FileAccess.open(temporary, FileAccess.WRITE)
		if file == null:
			_cleanup_temporary(temporary_paths)
			return _result(false, "migration_write_failed", "could not write %s" % temporary, affected)
		file.store_string(replaced)
		file.close()
		temporary_paths[path] = temporary
	var installed: Array[String] = []
	for path: String in temporary_paths:
		var absolute_path := ProjectSettings.globalize_path(path)
		var backup := "%s.migrate.bak" % path
		var absolute_backup := ProjectSettings.globalize_path(backup)
		var backup_error := DirAccess.rename_absolute(absolute_path, absolute_backup)
		if backup_error != OK:
			_rollback(installed, temporary_paths)
			return _result(false, "migration_backup_failed", "could not back up %s" % path, affected)
		var install_error := DirAccess.rename_absolute(
			ProjectSettings.globalize_path(temporary_paths[path]), absolute_path
		)
		if install_error != OK:
			DirAccess.rename_absolute(absolute_backup, absolute_path)
			_rollback(installed, temporary_paths)
			return _result(false, "migration_replace_failed", "could not replace %s" % path, affected)
		installed.append(path)
	var record_result := _write_migration_record(
		content_type, old_id, new_id, installed, migration_directory
	)
	if not record_result.get("ok", false):
		_rollback(installed, temporary_paths)
		return _result(
			false,
			"migration_record_failed",
			String(record_result.get("message", "could not write migration record")),
			affected
		)
	for path: String in installed:
		var backup := "%s.migrate.bak" % path
		if FileAccess.file_exists(backup):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(backup))
	var result := _result(true, "", "renamed %s to %s" % [old_id, new_id], affected)
	result["migration_file"] = String(record_result.get("path", ""))
	result["files"] = installed
	return result


func _valid_id(content_id: String, prefix: String) -> bool:
	if not content_id.begins_with(prefix + ".") or content_id != content_id.to_lower():
		return false
	for part: String in content_id.split("."):
		if part.is_empty() or not part.is_valid_identifier():
			return false
	return true


func _cleanup_temporary(temporary_paths: Dictionary[String, String]) -> void:
	for temporary: String in temporary_paths.values():
		if FileAccess.file_exists(temporary):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))


func _rollback(installed: Array[String], temporary_paths: Dictionary[String, String]) -> void:
	for path: String in installed:
		var backup := "%s.migrate.bak" % path
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if FileAccess.file_exists(backup):
			DirAccess.rename_absolute(
				ProjectSettings.globalize_path(backup), ProjectSettings.globalize_path(path)
			)
	_cleanup_temporary(temporary_paths)


func _replace_serialized_id(contents: String, old_id: StringName, new_id: StringName) -> String:
	var old_text := String(old_id)
	var new_text := String(new_id)
	return contents.replace('&"%s"' % old_text, '&"%s"' % new_text)


func _write_migration_record(
	content_type: String,
	old_id: StringName,
	new_id: StringName,
	files: Array[String],
	directory: String
) -> Dictionary:
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(directory)
	)
	if directory_error != OK:
		return {"ok": false, "message": error_string(directory_error)}
	var file_name := "%s_to_%s.json" % [
		String(old_id).replace(".", "_"), String(new_id).replace(".", "_")
	]
	var path := directory.path_join(file_name)
	if FileAccess.file_exists(path):
		return {"ok": false, "message": "migration record already exists: %s" % path}
	var temporary := "%s.tmp" % path
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "message": "could not open migration record: %s" % temporary}
	file.store_string(JSON.stringify({
		"migration_version": 1,
		"type": content_type,
		"old_id": String(old_id),
		"new_id": String(new_id),
		"files": files,
	}, "  "))
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		return {"ok": false, "message": error_string(write_error)}
	var install_error := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path)
	)
	if install_error != OK:
		if FileAccess.file_exists(temporary):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		return {"ok": false, "message": error_string(install_error)}
	return {"ok": true, "path": path}


func _result(ok: bool, code: String, message: String, affected: Array[Dictionary]) -> Dictionary:
	return {"ok": ok, "code": code, "message": message, "affected": affected}
