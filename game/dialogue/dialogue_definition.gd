class_name DialogueDefinition
extends Resource

@export var id: StringName
@export var blocks: Array[DialogueBlock] = []


func block(block_id: StringName) -> DialogueBlock:
	for candidate: DialogueBlock in blocks:
		if candidate != null and candidate.id == block_id:
			return candidate
	return null


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	var ids: Dictionary[StringName, bool] = {}
	for candidate: DialogueBlock in blocks:
		if candidate == null:
			errors.append("Dialogue %s contains an empty block" % id)
			continue
		if candidate.id.is_empty():
			errors.append("Dialogue %s contains a block with an empty id" % id)
		elif ids.has(candidate.id):
			errors.append("Dialogue %s repeats block %s" % [id, candidate.id])
		else:
			ids[candidate.id] = true
		if candidate.entries.is_empty():
			errors.append("Dialogue %s block %s has no entries" % [id, candidate.id])
	return errors
