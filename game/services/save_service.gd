class_name SaveService
extends Node

const DEFAULT_PATH := "user://framework_lab_save.json"

var last_diagnostic: Dictionary = {}
var _content_database: ContentDatabase


func configure(content_database: ContentDatabase) -> void:
	_content_database = content_database


func save_run(game_run: GameRun, path: String = DEFAULT_PATH) -> Error:
	_clear_diagnostic()
	if game_run == null:
		return _save_failure(ERR_INVALID_PARAMETER, "save_run_missing", "cannot save an empty GameRun", path)
	var content_errors := _content_errors(game_run)
	if not content_errors.is_empty():
		return _save_failure(
			ERR_INVALID_DATA,
			"save_content_invalid",
			String(content_errors[0]),
			path
		)
	var temporary := "%s.tmp" % path
	var backup := "%s.bak" % path
	var preparation_error := _prepare_replacement_paths(path, temporary, backup)
	if preparation_error != OK:
		return _save_failure(
			preparation_error,
			"save_recovery_failed",
			"could not prepare atomic save replacement: %s" % error_string(preparation_error),
			path
		)
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _save_failure(
			FileAccess.get_open_error(),
			"save_temporary_open_failed",
			"could not open the temporary save file",
			temporary
		)
	file.store_string(JSON.stringify(game_run.to_dictionary(), "  "))
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		_remove_if_exists(temporary)
		return _save_failure(
			write_error,
			"save_temporary_write_failed",
			"could not write the complete temporary save file",
			temporary
		)
	var verified := _load_run_file(temporary, false)
	if verified == null:
		_remove_if_exists(temporary)
		return _save_failure(
			ERR_FILE_CORRUPT,
			"save_temporary_verify_failed",
			"temporary save file did not round-trip",
			temporary
		)
	var replacement_error := _replace_file(temporary, path, backup)
	if replacement_error != OK:
		return _save_failure(
			replacement_error,
			"save_atomic_replace_failed",
			"could not install the new save; the previous save was restored",
			path
		)
	_clear_diagnostic()
	return OK


func load_run(path: String = DEFAULT_PATH) -> GameRun:
	_clear_diagnostic()
	var recovery_error := _prepare_replacement_paths(
		path,
		"%s.tmp" % path,
		"%s.bak" % path
	)
	if recovery_error != OK:
		_set_diagnostic(
			"save_recovery_failed",
			"interrupted save replacement could not be recovered: %s" % error_string(recovery_error),
			path
		)
		return null
	return _load_run_file(path, true)


func _load_run_file(path: String, record_diagnostic: bool) -> GameRun:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		if record_diagnostic:
			_set_diagnostic("save_open_failed", "save file could not be opened", path)
		return null
	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())
	file.close()
	if parse_error != OK or not json.data is Dictionary:
		if record_diagnostic:
			_set_diagnostic(
				"save_json_invalid",
				"save file is invalid JSON: %s" % json.get_error_message(),
				path
			)
		return null
	var data: Dictionary = json.data
	if (
		int(data.get("save_version", -1)) != GameRun.SAVE_VERSION
		or int(data.get("content_version", -1)) != GameRun.CONTENT_VERSION
	):
		if record_diagnostic:
			_set_diagnostic(
				"save_schema_unsupported",
				"save file uses an unsupported save or content schema",
				path
			)
		return null
	var game_run := GameRun.from_dictionary(data)
	if game_run == null:
		if record_diagnostic:
			_set_diagnostic("save_payload_invalid", "save payload is incomplete or invalid", path)
		return null
	var content_errors := _content_errors(game_run)
	if not content_errors.is_empty():
		if record_diagnostic:
			_set_diagnostic(
				"save_content_invalid",
				String(content_errors[0]),
				path,
				String(game_run.location.map_id)
			)
		return null
	return game_run


func _prepare_replacement_paths(path: String, temporary: String, backup: String) -> Error:
	var remove_error := _remove_if_exists(temporary)
	if remove_error != OK:
		return remove_error
	if not FileAccess.file_exists(backup):
		return OK
	if FileAccess.file_exists(path):
		return _remove_if_exists(backup)
	return _rename_absolute(
		ProjectSettings.globalize_path(backup),
		ProjectSettings.globalize_path(path)
	)


func _replace_file(temporary: String, path: String, backup: String) -> Error:
	var absolute_temporary := ProjectSettings.globalize_path(temporary)
	var absolute_path := ProjectSettings.globalize_path(path)
	var absolute_backup := ProjectSettings.globalize_path(backup)
	var had_previous := FileAccess.file_exists(path)
	if had_previous:
		var backup_error := _rename_absolute(absolute_path, absolute_backup)
		if backup_error != OK:
			_remove_if_exists(temporary)
			return backup_error
	var install_error := _rename_absolute(absolute_temporary, absolute_path)
	if install_error != OK:
		if had_previous:
			var rollback_error := _rename_absolute(absolute_backup, absolute_path)
			if rollback_error != OK:
				_set_diagnostic(
					"save_atomic_rollback_failed",
					"new save installation and previous save rollback both failed",
					path
				)
		_remove_if_exists(temporary)
		return install_error
	if had_previous:
		_remove_if_exists(backup)
	return OK


func _is_known_map(map_id: StringName) -> bool:
	return _content_database == null or _content_database.has_map(map_id)


func _content_errors(game_run: GameRun) -> PackedStringArray:
	if _content_database == null:
		return PackedStringArray()
	return _content_database.validate_game_run(game_run)


func _remove_if_exists(path: String) -> Error:
	if not FileAccess.file_exists(path):
		return OK
	return _remove_absolute(ProjectSettings.globalize_path(path))


func _rename_absolute(from: String, to: String) -> Error:
	return DirAccess.rename_absolute(from, to)


func _remove_absolute(path: String) -> Error:
	return DirAccess.remove_absolute(path)


func _save_failure(error: Error, code: String, message: String, path: String) -> Error:
	if last_diagnostic.get("code") != "save_atomic_rollback_failed":
		_set_diagnostic(code, message, path)
	return error


func _set_diagnostic(
	code: String,
	message: String,
	file: String,
	content_id: String = ""
) -> void:
	last_diagnostic = {
		"code": code,
		"message": message,
		"file": file,
		"field": "",
	}
	if not content_id.is_empty():
		last_diagnostic["content_id"] = content_id


func _clear_diagnostic() -> void:
	last_diagnostic = {}
