class_name ContentDatabase
extends Resource

@export var maps: Array[MapDefinition] = []

var _maps_by_id: Dictionary[StringName, MapDefinition] = {}


func build_index() -> PackedStringArray:
	_maps_by_id.clear()
	var errors := PackedStringArray()
	for definition: MapDefinition in maps:
		if definition == null:
			errors.append("ContentDatabase contains an empty map reference")
			continue
		if definition.id.is_empty():
			errors.append("MapDefinition has an empty id")
			continue
		if _maps_by_id.has(definition.id):
			errors.append("Duplicate map id: %s" % definition.id)
			continue
		if definition.scene == null:
			errors.append("Map %s has no scene" % definition.id)
			continue
		_maps_by_id[definition.id] = definition
	return errors


func map(id: StringName) -> MapDefinition:
	return _maps_by_id.get(id)


func has_map(id: StringName) -> bool:
	return _maps_by_id.has(id)
