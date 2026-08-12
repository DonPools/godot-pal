class_name ContentSaveMigrator
extends RefCounted


func migrate(data: Dictionary, migration_directory: String) -> Dictionary:
	var records_result := _load_records(migration_directory)
	if not records_result.get("ok", false):
		return records_result
	var records: Array[Dictionary] = []
	records.assign(records_result.get("records", []))
	var migrated: Variant = data.duplicate(true)
	var applied: Array[Dictionary] = []
	for _pass: int in range(records.size() + 1):
		var changed_in_pass := false
		for record: Dictionary in records:
			var result := _replace_value(
				migrated,
				String(record.get("old_id", "")),
				String(record.get("new_id", "")),
				String(record.get("type", "")) == "map"
			)
			if not result.get("ok", true):
				return _failure(
					String(result.get("code", "save_migration_conflict")),
					String(result.get("message", "save migration produced a key conflict")),
					String(record.get("file", migration_directory))
				)
			migrated = result.get("value")
			if result.get("changed", false):
				changed_in_pass = true
				if record not in applied:
					applied.append(record)
		if not changed_in_pass:
			return {"ok": true, "data": migrated, "applied": applied, "diagnostics": []}
	return _failure(
		"save_migration_cycle",
		"content ID migrations did not converge; check for a rename cycle",
		migration_directory
	)


func _load_records(directory_path: String) -> Dictionary:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return {"ok": true, "records": [], "diagnostics": []}
	var files := directory.get_files()
	files.sort()
	var records: Array[Dictionary] = []
	var targets: Dictionary[String, String] = {}
	for file_name: String in files:
		if file_name.get_extension().to_lower() != "json":
			continue
		var path := directory_path.path_join(file_name)
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			return _failure("save_migration_read_failed", "could not read migration record", path)
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if not parsed is Dictionary:
			return _failure("save_migration_invalid", "migration record is not valid JSON", path)
		var record := parsed as Dictionary
		var content_type := String(record.get("type", ""))
		var old_id := String(record.get("old_id", ""))
		var new_id := String(record.get("new_id", ""))
		if (
			int(record.get("migration_version", -1)) != 1
			or content_type not in ContentCatalog.TYPES
			or old_id.is_empty()
			or new_id.is_empty()
			or old_id == new_id
		):
			return _failure("save_migration_invalid", "migration record is incomplete", path)
		var prefix := "item" if content_type == "equipment" else content_type
		if not old_id.begins_with(prefix + ".") or not new_id.begins_with(prefix + "."):
			return _failure(
				"save_migration_invalid",
				"migration IDs do not match the declared content type",
				path
			)
		if targets.has(old_id) and targets[old_id] != new_id:
			return _failure(
				"save_migration_conflict",
				"multiple migration targets are configured for %s" % old_id,
				path
			)
		targets[old_id] = new_id
		records.append({
			"type": content_type,
			"old_id": old_id,
			"new_id": new_id,
			"file": path,
		})
	return {"ok": true, "records": records, "diagnostics": []}


func _replace_value(value: Variant, old_id: String, new_id: String, map_id: bool) -> Dictionary:
	if value is String:
		if value == old_id:
			return {"ok": true, "value": new_id, "changed": true}
		if map_id and value.begins_with(old_id + "::"):
			return {"ok": true, "value": new_id + value.trim_prefix(old_id), "changed": true}
		return {"ok": true, "value": value, "changed": false}
	if value is Array:
		var array := value as Array
		var changed := false
		for index: int in range(array.size()):
			var result := _replace_value(array[index], old_id, new_id, map_id)
			if not result.get("ok", true):
				return result
			array[index] = result.get("value")
			changed = changed or result.get("changed", false)
		return {"ok": true, "value": array, "changed": changed}
	if value is Dictionary:
		var dictionary := value as Dictionary
		var replaced: Dictionary = {}
		var changed := false
		for key: Variant in dictionary:
			var key_result := _replace_value(key, old_id, new_id, map_id)
			var value_result := _replace_value(dictionary[key], old_id, new_id, map_id)
			if not key_result.get("ok", true):
				return key_result
			if not value_result.get("ok", true):
				return value_result
			var new_key: Variant = key_result.get("value")
			if replaced.has(new_key):
				return {
					"ok": false,
					"code": "save_migration_key_conflict",
					"message": "content ID migration would overwrite an existing save key",
				}
			replaced[new_key] = value_result.get("value")
			changed = (
				changed
				or key_result.get("changed", false)
				or value_result.get("changed", false)
			)
		return {"ok": true, "value": replaced, "changed": changed}
	return {"ok": true, "value": value, "changed": false}


func _failure(code: String, message: String, file: String) -> Dictionary:
	return {
		"ok": false,
		"code": code,
		"data": {},
		"diagnostics": [{
			"code": code,
			"message": message,
			"file": file,
			"field": "",
		}],
	}
