class_name GameRun
extends RefCounted

const SAVE_VERSION := 5
const PREVIOUS_SAVE_VERSION := 4
const TWO_DIMENSIONAL_SAVE_VERSION := 3
const LEGACY_SAVE_VERSION := 2
const CONTENT_VERSION := 3

var party := PartyState.new()
var inventory := InventoryState.new()
var economy := EconomyState.new()
var story := StoryState.new()
var flags := GameFlags.new()
var world := WorldState.new()
var location := LocationState.new()
var randomness := RandomState.new()


static func new_game(
	database: ContentDatabase,
	random_seed: int = 0
) -> GameRun:
	var run := GameRun.new()
	var resolved_seed := random_seed
	if resolved_seed == 0:
		resolved_seed = int(Time.get_unix_time_from_system() * 1000.0) ^ Time.get_ticks_usec()
	run.randomness.initialize(resolved_seed)
	if database == null:
		return run
	for definition: ActorDefinition in database.starting_party:
		if definition != null:
			var state := ActorState.from_definition(definition)
			run.party.add_member(state)
			state.hp = CultivationRules.max_hp(definition, state, database)
			state.mp = CultivationRules.max_mp(definition, state, database)
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
		"randomness": randomness.to_dictionary(),
	}


static func from_dictionary(data: Dictionary, database: ContentDatabase = null) -> GameRun:
	var save_version := int(data.get("save_version", -1))
	if (
		save_version not in [
			LEGACY_SAVE_VERSION,
			TWO_DIMENSIONAL_SAVE_VERSION,
			PREVIOUS_SAVE_VERSION,
			SAVE_VERSION,
		]
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
	var randomness_data: Variant = data.get("randomness", {})
	if not (
		party_data is Dictionary
		and inventory_data is Dictionary
		and economy_data is Dictionary
		and location_data is Dictionary
		and story_data is Dictionary
		and flags_data is Dictionary
		and world_data is Dictionary
		and randomness_data is Dictionary
	):
		return null
	var run := GameRun.new()
	if not run.party.restore(party_data, database):
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
	if not randomness_data.is_empty() and not run.randomness.restore(randomness_data):
		return null
	return run
