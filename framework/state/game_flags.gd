class_name GameFlags
extends RefCounted

var _values: Dictionary[StringName, Variant] = {}


func is_set(flag_id: StringName) -> bool:
	return bool(_values.get(flag_id, false))


func get_value(flag_id: StringName, default_value: Variant = null) -> Variant:
	return _values.get(flag_id, default_value)


func set_value(flag_id: StringName, value: Variant = true) -> void:
	_values[flag_id] = value


func clear(flag_id: StringName) -> void:
	_values.erase(flag_id)


func to_dictionary() -> Dictionary:
	var result: Dictionary = {}
	for flag_id: StringName in _values:
		result[String(flag_id)] = _values[flag_id]
	return result


func restore(data: Dictionary) -> void:
	_values.clear()
	for raw_id: Variant in data:
		if raw_id is String:
			_values[StringName(raw_id)] = data[raw_id]
