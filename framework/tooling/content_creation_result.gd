class_name ContentCreationResult
extends RefCounted

var resource: Resource
var diagnostics: Array[Dictionary] = []


func reject(
	code: String,
	message: String,
	file: String,
	field: String,
	content_id: StringName = &""
) -> void:
	var diagnostic := {
		"code": code,
		"message": message,
		"file": file,
		"field": field,
	}
	if not content_id.is_empty():
		diagnostic["content_id"] = String(content_id)
	diagnostics.append(diagnostic)


func succeeded() -> bool:
	return resource != null and diagnostics.is_empty()
