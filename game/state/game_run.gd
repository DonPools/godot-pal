class_name GameRun
extends RefCounted

const SAVE_VERSION := 1

var story := StoryState.new()
var flags := GameFlags.new()
var world := WorldState.new()
var location := LocationState.new()


func to_dictionary() -> Dictionary:
	return {
		"save_version": SAVE_VERSION,
		"story": story.to_dictionary(),
		"flags": flags.to_dictionary(),
		"world": world.to_dictionary(),
		"location": location.to_dictionary(),
	}


static func from_dictionary(data: Dictionary) -> GameRun:
	if int(data.get("save_version", -1)) != SAVE_VERSION:
		return null
	var location_data: Variant = data.get("location")
	var story_data: Variant = data.get("story")
	var flags_data: Variant = data.get("flags")
	var world_data: Variant = data.get("world")
	if not (location_data is Dictionary and story_data is Dictionary):
		return null
	if not (flags_data is Dictionary and world_data is Dictionary):
		return null
	var run := GameRun.new()
	if not run.location.restore(location_data):
		return null
	run.story.restore(story_data)
	run.flags.restore(flags_data)
	run.world.restore(world_data)
	return run
