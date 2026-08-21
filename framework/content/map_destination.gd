@tool
class_name MapDestination
extends Resource

@export var map_id: StringName
@export var spawn_id: StringName


static func create(destination_map_id: StringName, destination_spawn_id: StringName = &"") -> MapDestination:
	var destination := MapDestination.new()
	destination.map_id = destination_map_id
	destination.spawn_id = destination_spawn_id
	return destination
