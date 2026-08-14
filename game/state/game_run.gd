class_name GameRun
extends RefCounted

const SAVE_VERSION := 2
const CONTENT_VERSION := 3

var party := PartyState.new()
var inventory := InventoryState.new()
var economy := EconomyState.new()
var story := StoryState.new()
var flags := GameFlags.new()
var world := WorldState.new()
var location := LocationState.new()


static func new_game(database: ContentDatabase) -> GameRun:
	var run := GameRun.new()
	if database == null:
		return run
	for definition: ActorDefinition in database.starting_party:
		if definition != null:
			run.party.add_member(ActorState.from_definition(definition))
	run.economy.money = database.starting_money
	return run


func to_dictionary() -> Dictionary:
	return {
		"save_version": SAVE_VERSION,
		"content_version": CONTENT_VERSION,
		"party": party.to_dictionary(),
		"inventory": inventory.to_dictionary(),
		"economy": economy.to_dictionary(),
		"story": story.to_dictionary(),
		"flags": flags.to_dictionary(),
		"world": world.to_dictionary(),
		"location": location.to_dictionary(),
	}


static func from_dictionary(data: Dictionary) -> GameRun:
	if (
		int(data.get("save_version", -1)) != SAVE_VERSION
		or int(data.get("content_version", -1)) != CONTENT_VERSION
	):
		return null
	var party_data: Variant = data.get("party")
	var inventory_data: Variant = data.get("inventory")
	var economy_data: Variant = data.get("economy")
	var location_data: Variant = data.get("location")
	var story_data: Variant = data.get("story")
	var flags_data: Variant = data.get("flags")
	var world_data: Variant = data.get("world")
	if not (
		party_data is Dictionary
		and inventory_data is Dictionary
		and economy_data is Dictionary
		and location_data is Dictionary
		and story_data is Dictionary
		and flags_data is Dictionary
		and world_data is Dictionary
	):
		return null
	var run := GameRun.new()
	if not run.party.restore(party_data):
		return null
	if not run.inventory.restore(inventory_data):
		return null
	if not run.economy.restore(economy_data):
		return null
	if not run.location.restore(location_data):
		return null
	run.story.restore(story_data)
	run.flags.restore(flags_data)
	run.world.restore(world_data)
	return run
