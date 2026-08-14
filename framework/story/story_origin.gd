class_name StoryOrigin
extends RefCounted

var map_id: StringName
var source_entity_id: StringName
var source_actor_id: StringName


static func create(
	p_map_id: StringName,
	p_source_entity_id: StringName = &"",
	p_source_actor_id: StringName = &""
) -> StoryOrigin:
	var origin := StoryOrigin.new()
	origin.map_id = p_map_id
	origin.source_entity_id = p_source_entity_id
	origin.source_actor_id = p_source_actor_id
	return origin
