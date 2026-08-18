class_name LocationState
extends RefCounted

var map_id: StringName
var spawn_id: StringName = &"default"
var position: Vector3 = Vector3.ZERO
var direction: StringName = &"south"
var has_exact_position: bool = false
var migrated_from_2d_position: bool = false


func to_dictionary() -> Dictionary:
	return {
		"map_id": String(map_id),
		"spawn_id": String(spawn_id),
		"position": [position.x, position.y, position.z],
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
	if not (raw_position is Array and raw_position.size() in [2, 3]):
		return false
	map_id = StringName(raw_map)
	spawn_id = StringName(raw_spawn)
	direction = StringName(raw_direction)
	var requested_exact := bool(data.get("has_exact_position", false))
	if raw_position.size() == 3:
		position = Vector3(
			float(raw_position[0]),
			float(raw_position[1]),
			float(raw_position[2])
		)
		has_exact_position = requested_exact
		migrated_from_2d_position = false
	else:
		# A 2D pixel coordinate has no reliable meaning in a rebuilt 3D map.
		position = Vector3.ZERO
		has_exact_position = false
		migrated_from_2d_position = requested_exact
	return true
