class_name StoryState
extends RefCounted

var _stages: Dictionary[StringName, StringName] = {}


func get_stage(story_id: StringName, initial_stage: StringName) -> StringName:
	return _stages.get(story_id, initial_stage)


func set_stage(story_id: StringName, stage_id: StringName) -> void:
	_stages[story_id] = stage_id


func to_dictionary() -> Dictionary:
	var result: Dictionary = {}
	for story_id: StringName in _stages:
		result[String(story_id)] = String(_stages[story_id])
	return result


func restore(data: Dictionary) -> void:
	_stages.clear()
	for raw_id: Variant in data:
		var raw_stage: Variant = data[raw_id]
		if raw_id is String and raw_stage is String:
			_stages[StringName(raw_id)] = StringName(raw_stage)
