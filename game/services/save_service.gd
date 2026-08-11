class_name SaveService
extends Node

const DEFAULT_PATH := "user://framework_lab_save.json"


func save_run(game_run: GameRun, path: String = DEFAULT_PATH) -> Error:
	var payload := JSON.stringify(game_run.to_dictionary(), "  ")
	var temporary := "%s.tmp" % path
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(payload)
	file.close()
	var check := FileAccess.open(temporary, FileAccess.READ)
	if check == null:
		return FileAccess.get_open_error()
	var parsed: Variant = JSON.parse_string(check.get_as_text())
	check.close()
	if not (parsed is Dictionary) or GameRun.from_dictionary(parsed) == null:
		return ERR_FILE_CORRUPT
	if FileAccess.file_exists(path):
		var remove_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if remove_error != OK:
			return remove_error
	return DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temporary),
		ProjectSettings.globalize_path(path)
	)


func load_run(path: String = DEFAULT_PATH) -> GameRun:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return null
	return GameRun.from_dictionary(parsed)
