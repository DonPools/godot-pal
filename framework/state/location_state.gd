class_name LocationState
extends RefCounted

var map_id: StringName
var spawn_id: StringName = &"default"
var position: Vector2 = Vector2.ZERO
var direction: StringName = &"south"
var has_exact_position: bool = false


func to_dictionary() -> Dictionary:
	return {
		"map_id": String(map_id),
		"spawn_id": String(spawn_id),
		"position": [position.x, position.y],
		"direction": String(direction),
		"has_exact_position": has_exact_position,
	}


func restore(data: Dictionary) -> bool:
	var raw_map: Variant = data.get("map_id")
	var raw_spawn: Variant = data.get("spawn_id")
	var raw_position: Variant = data.get("position")
	var raw_direction: Variant = data.get("direction")
	if not (raw_map is String and raw_spawn is String and raw_direction is String):
		return false
	if not (raw_position is Array and raw_position.size() == 2):
		return false
	map_id = StringName(raw_map)
	spawn_id = StringName(raw_spawn)
	position = Vector2(float(raw_position[0]), float(raw_position[1]))
	direction = StringName(raw_direction)
	has_exact_position = bool(data.get("has_exact_position", false))
	return true
