class_name WorldState
extends RefCounted

var _completed_entities: Dictionary[String, bool] = {}


func is_completed(map_id: StringName, entity_id: StringName) -> bool:
	return _completed_entities.get(_key(map_id, entity_id), false)


func complete(map_id: StringName, entity_id: StringName) -> bool:
	var key := _key(map_id, entity_id)
	if _completed_entities.has(key):
		return false
	_completed_entities[key] = true
	return true


func to_dictionary() -> Dictionary:
	return _completed_entities.duplicate(true)


func restore(data: Dictionary) -> void:
	_completed_entities.clear()
	for raw_key: Variant in data:
		if raw_key is String and bool(data[raw_key]):
			_completed_entities[raw_key] = true


func _key(map_id: StringName, entity_id: StringName) -> String:
	return "%s::%s" % [map_id, entity_id]
